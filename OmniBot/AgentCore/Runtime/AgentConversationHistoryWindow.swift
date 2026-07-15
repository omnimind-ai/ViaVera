import Foundation

/// Builds a bounded prompt history without splitting a user turn or an
/// assistant/tool transaction. Token counts are conservative estimates; the
/// provider remains the source of truth for exact tokenization.
nonisolated public enum AgentConversationHistoryWindow {
    public static func select(
        history: [AgentMessage],
        currentUserMessage: AgentMessage,
        systemMessages: [AgentMessage],
        tools: [AgentToolDefinition],
        contextWindow: Int?,
        maxOutputTokens: Int?,
        additionalReserveTokens: Int = 0
    ) -> [AgentMessage] {
        var repaired = repairToolTransactions(history.filter { $0.role != .system })

        let currentID: UUID
        if repaired.contains(where: { $0.id == currentUserMessage.id }) {
            currentID = currentUserMessage.id
        } else if let matchingUser = repaired.last(where: {
            $0.role == .user && normalized($0.content) == normalized(currentUserMessage.content)
        }) {
            currentID = matchingUser.id
        } else {
            repaired.append(currentUserMessage)
            currentID = currentUserMessage.id
        }

        guard let contextWindow, contextWindow > 0 else {
            return repaired
        }

        let turns = userTurns(from: repaired)
        guard let currentTurnIndex = turns.lastIndex(where: {
            $0.contains(where: { $0.id == currentID })
        }) else {
            return [currentUserMessage]
        }

        let systemCost = estimatedTokens(for: systemMessages)
        let toolSchemaCost = estimatedTokens(for: tools)
        let requestedOutputReserve = maxOutputTokens ?? max(512, contextWindow / 4)
        let outputReserve = min(max(0, requestedOutputReserve), contextWindow / 2)
        let protocolReserve = min(1_024, max(128, contextWindow / 20))
        let historyBudget = max(
            0,
            contextWindow
                - systemCost
                - toolSchemaCost
                - outputReserve
                - protocolReserve
                - max(0, additionalReserveTokens)
        )

        var selectedIndices: [Int] = [currentTurnIndex]
        var remaining = max(0, historyBudget - estimatedTokens(for: turns[currentTurnIndex]))

        if currentTurnIndex > 0 {
            for index in stride(from: currentTurnIndex - 1, through: 0, by: -1) {
                let cost = estimatedTokens(for: turns[index])
                guard cost <= remaining else { break }
                selectedIndices.append(index)
                remaining -= cost
            }
        }

        return selectedIndices
            .sorted()
            .flatMap { turns[$0] }
    }

    /// Verifies the exact selected request estimate before transport. `select`
    /// always preserves the current user turn, so an exceptionally large turn
    /// or fixed system/tool schema still needs an explicit fail-fast check.
    public static func fitsContext(
        messages: [AgentMessage],
        tools: [AgentToolDefinition],
        contextWindow: Int?,
        maxOutputTokens: Int?,
        additionalReserveTokens: Int = 0
    ) -> Bool {
        guard let contextWindow, contextWindow > 0 else { return true }
        let requestedOutputReserve = maxOutputTokens ?? max(512, contextWindow / 4)
        let outputReserve = min(max(0, requestedOutputReserve), contextWindow / 2)
        let protocolReserve = min(1_024, max(128, contextWindow / 20))
        let available = contextWindow
            - outputReserve
            - protocolReserve
            - max(0, additionalReserveTokens)
        guard available >= 0 else { return false }
        return estimatedTokens(for: messages) + estimatedTokens(for: tools) <= available
    }

    /// Makes persisted history acceptable to OpenAI-compatible APIs after a
    /// cancellation or crash. Every assistant tool call gets exactly one
    /// adjacent result; unrelated/orphan tool messages are dropped.
    public static func repairToolTransactions(_ messages: [AgentMessage]) -> [AgentMessage] {
        var repaired: [AgentMessage] = []
        var index = 0

        while index < messages.count {
            let message = messages[index]
            guard message.role != .tool else {
                index += 1
                continue
            }

            guard message.role == .assistant, !message.toolCalls.isEmpty else {
                repaired.append(message)
                index += 1
                continue
            }

            var assistant = message
            var seenCallIDs = Set<String>()
            assistant.toolCalls = assistant.toolCalls.filter { call in
                !call.id.isEmpty && seenCallIDs.insert(call.id).inserted
            }
            repaired.append(assistant)

            let expectedIDs = Set(assistant.toolCalls.map(\.id))
            var resultsByCallID: [String: AgentMessage] = [:]
            var nextIndex = index + 1
            while nextIndex < messages.count, messages[nextIndex].role == .tool {
                let result = messages[nextIndex]
                if let callID = result.toolCallID,
                   expectedIDs.contains(callID),
                   resultsByCallID[callID] == nil {
                    resultsByCallID[callID] = result
                }
                nextIndex += 1
            }

            for call in assistant.toolCalls {
                if let result = resultsByCallID[call.id] {
                    repaired.append(result)
                } else {
                    repaired.append(.tool(
                        callID: call.id,
                        name: call.name,
                        content: syntheticInterruptedToolResult
                    ))
                }
            }
            index = nextIndex
        }

        return repaired
    }

    private static let syntheticInterruptedToolResult =
        #"{"success":false,"confirmed":false,"outcome":"unknown","error":"The previous Agent run ended before this tool result was persisted. The action may have completed. Inspect current state before deciding whether to retry; never blindly repeat a non-idempotent action."}"#

    private static func userTurns(from messages: [AgentMessage]) -> [[AgentMessage]] {
        var turns: [[AgentMessage]] = []
        var current: [AgentMessage] = []

        for message in messages {
            if message.role == .user {
                if !current.isEmpty {
                    turns.append(current)
                }
                current = [message]
            } else if !current.isEmpty {
                current.append(message)
            }
        }
        if !current.isEmpty {
            turns.append(current)
        }
        return turns
    }

    private static func estimatedTokens(for messages: [AgentMessage]) -> Int {
        messages.reduce(0) { partial, message in
            var bytes = message.content?.utf8.count ?? 0
            bytes += message.reasoningContent?.utf8.count ?? 0
            if let providerMetadata = message.providerMetadata {
                bytes += (try? JSONEncoder().encode(providerMetadata).count) ?? 0
            }
            bytes += message.name?.utf8.count ?? 0
            bytes += message.toolCallID?.utf8.count ?? 0
            for call in message.toolCalls {
                bytes += call.id.utf8.count + call.name.utf8.count + call.arguments.utf8.count
            }
            return partial + 12 + max(1, (bytes + 2) / 3)
        }
    }

    private static func estimatedTokens(for tools: [AgentToolDefinition]) -> Int {
        guard !tools.isEmpty else { return 0 }
        let byteCount = (try? JSONEncoder().encode(tools).count)
            ?? tools.reduce(0) { $0 + $1.name.utf8.count + $1.description.utf8.count }
        return 32 + max(1, (byteCount + 2) / 3)
    }

    private static func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            ?? ""
    }
}
