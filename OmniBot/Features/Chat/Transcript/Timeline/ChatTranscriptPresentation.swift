import Foundation

struct ChatTranscriptPresentation {
    let messages: [ChatMessagePresentation]
    let timelineEntries: [ChatTimelineEntry]
    let agentTurns: [AgentTurnPresentation]
    let latestUserMessageID: UUID?
    let latestTurnTools: [ToolCallPresentation]
    let runIsActive: Bool

    var activeAgentTurn: AgentTurnPresentation? {
        agentTurns.first(where: \.isActive)
    }

    func agentTurn(id: UUID) -> AgentTurnPresentation? {
        agentTurns.first { $0.id == id }
    }

    func toolActivityTurn(
        preferredCompletedTurnID: UUID?
    ) -> AgentTurnPresentation? {
        // An active run with no started tool must hide the strip instead of
        // falling back to a previously expanded completed turn.
        if runIsActive {
            return activeAgentTurn
        }
        guard let preferredCompletedTurnID else { return nil }
        return agentTurn(id: preferredCompletedTurnID)
    }

    init(
        messages orderedMessages: [MessageRecord],
        runIsActive: Bool,
        liveToolActivity: ChatToolLiveSnapshot?
    ) {
        let usageMessageIDs = Self.finalAssistantMessageIDs(in: orderedMessages)
        let lastUserIndex = orderedMessages.lastIndex { $0.role == .user }
        latestUserMessageID = lastUserIndex.map { orderedMessages[$0].id }

        var rows: [ChatMessagePresentation] = []
        var latestTools: [ToolCallPresentation] = []
        for (index, message) in orderedMessages.enumerated() where message.role != .tool {
            let decodedAssistant = message.role == .assistant
                ? try? message.decodeMessage()
                : nil
            let calls: [ToolCallPresentation]
            if let decoded = decodedAssistant {
                let resultsByCallIndex = Self.nearestToolResults(
                    for: decoded.toolCalls,
                    afterAssistantAt: index,
                    in: orderedMessages
                )
                let belongsToActiveRun = runIsActive
                    && liveToolActivity?.assistantMessageIDs.contains(message.id) == true
                calls = decoded.toolCalls.enumerated().map { callIndex, call in
                    let isActiveOccurrence = belongsToActiveRun
                        && liveToolActivity?.activeAssistantMessageID == message.id
                        && liveToolActivity?.activeCallID == call.id
                    return ToolCallPresentation(
                        assistantMessageID: message.id,
                        callIndex: callIndex,
                        call: call,
                        result: resultsByCallIndex[callIndex],
                        runIsActive: belongsToActiveRun,
                        activeCallID: isActiveOccurrence ? call.id : nil,
                        liveTerminalOutput: isActiveOccurrence
                            ? liveToolActivity?.terminalOutput
                            : nil
                    )
                }
            } else {
                calls = []
            }

            let usage: TurnUsagePresentation?
            if usageMessageIDs.contains(message.id) {
                let candidate = TurnUsagePresentation(
                    usage: AgentUsage(
                        promptTokens: message.promptTokens,
                        completionTokens: message.completionTokens,
                        totalTokens: AgentUsage.saturatingSum(
                            message.promptTokens,
                            message.completionTokens
                        ),
                        cachedTokens: message.cachedTokens
                    )
                )
                usage = candidate.isEmpty ? nil : candidate
            } else {
                usage = nil
            }

            rows.append(
                ChatMessagePresentation(
                    message: message,
                    content: message.content,
                    reasoningContent: decodedAssistant?.reasoningContent,
                    isReasoningStreaming: message.role == .assistant
                        && message.status == .streaming
                        && !Self.hasVisibleText(message.content),
                    toolCalls: calls,
                    turnUsage: usage,
                    showsStatus: true
                )
            )

            if let lastUserIndex, index > lastUserIndex {
                latestTools.append(contentsOf: calls)
            }
        }

        let timeline = Self.buildTimeline(
            from: rows,
            runIsActive: runIsActive,
            latestUserMessageID: latestUserMessageID,
            liveAssistantMessageIDs: liveToolActivity?.assistantMessageIDs ?? []
        )

        self.messages = rows
        timelineEntries = timeline.entries
        agentTurns = timeline.turns
        latestTurnTools = latestTools
        self.runIsActive = runIsActive
    }

    private static func buildTimeline(
        from rows: [ChatMessagePresentation],
        runIsActive: Bool,
        latestUserMessageID: UUID?,
        liveAssistantMessageIDs: Set<UUID>
    ) -> (entries: [ChatTimelineEntry], turns: [AgentTurnPresentation]) {
        var entries: [ChatTimelineEntry] = []
        var turns: [AgentTurnPresentation] = []
        var pendingAssistants: [ChatMessagePresentation] = []
        var turnAnchorID: UUID?

        func appendPendingAssistants() {
            guard !pendingAssistants.isEmpty else { return }

            let displayableAssistants = pendingAssistants.filter {
                $0.message.content?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false
                    || $0.reasoningContent?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty == false
                    || $0.toolCalls.contains(where: \.wasStarted)
                    || $0.message.status == .pending
                    || $0.message.status == .streaming
            }
            guard !displayableAssistants.isEmpty else {
                pendingAssistants.removeAll(keepingCapacity: true)
                return
            }

            let turnID = turnAnchorID ?? displayableAssistants[0].id
            let belongsToLiveRun = displayableAssistants.contains {
                liveAssistantMessageIDs.contains($0.id)
            }
            let isActive = runIsActive
                && (belongsToLiveRun || turnID == latestUserMessageID)

            let processMessages: [ChatMessagePresentation]
            let visibleMessages: [ChatMessagePresentation]
            // Tool rounds, intermediate assistant text, and the terminal
            // assistant's reasoning form the collapsible process. Only the
            // terminal answer remains visible after the Agent turn completes.
            if let terminalMessage = displayableAssistants.last,
               terminalMessage.toolCalls.isEmpty {
                var process = Array(displayableAssistants.dropLast())
                let hasTerminalReasoning = terminalMessage.reasoningContent?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false
                if hasTerminalReasoning {
                    process.append(
                        ChatMessagePresentation(
                            message: terminalMessage.message,
                            content: nil,
                            reasoningContent: terminalMessage.reasoningContent,
                            isReasoningStreaming: terminalMessage.isReasoningStreaming,
                            toolCalls: [],
                            turnUsage: terminalMessage.turnUsage,
                            showsStatus: false
                        )
                    )
                }
                processMessages = process

                let hasTerminalContent = terminalMessage.content?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false
                let needsVisibleProgress = !hasTerminalReasoning
                    && (terminalMessage.message.status == .pending
                        || terminalMessage.message.status == .streaming)
                let needsVisibleStatus = terminalMessage.message.status == .failed
                    || terminalMessage.message.status == .interrupted
                if hasTerminalContent || needsVisibleProgress || needsVisibleStatus {
                    visibleMessages = [
                        ChatMessagePresentation(
                            message: terminalMessage.message,
                            content: terminalMessage.content,
                            reasoningContent: nil,
                            isReasoningStreaming: false,
                            toolCalls: [],
                            turnUsage: terminalMessage.turnUsage,
                            showsStatus: true
                        )
                    ]
                } else {
                    visibleMessages = []
                }
            } else {
                processMessages = displayableAssistants
                visibleMessages = []
            }

            if processMessages.isEmpty {
                entries.append(contentsOf: visibleMessages.map(ChatTimelineEntry.message))
            } else {
                let turn = AgentTurnPresentation(
                    id: turnID,
                    processMessages: processMessages,
                    visibleMessages: visibleMessages,
                    isActive: isActive
                )
                turns.append(turn)
                entries.append(.agentTurn(turn))
            }
            pendingAssistants.removeAll(keepingCapacity: true)
        }

        for row in rows {
            if row.message.role == .assistant {
                pendingAssistants.append(row)
                continue
            }

            appendPendingAssistants()
            entries.append(.message(row))
            if row.message.role == .user {
                turnAnchorID = row.id
            }
        }
        appendPendingAssistants()
        return (entries, turns)
    }

    private static func nearestToolResults(
        for calls: [AgentToolCall],
        afterAssistantAt assistantIndex: Int,
        in messages: [MessageRecord]
    ) -> [Int: MessageRecord] {
        guard !calls.isEmpty, assistantIndex + 1 < messages.count else { return [:] }

        var candidates: [MessageRecord] = []
        var messageIndex = assistantIndex + 1
        while messageIndex < messages.count, messages[messageIndex].role == .tool {
            candidates.append(messages[messageIndex])
            messageIndex += 1
        }

        var usedCandidateIndices: Set<Int> = []
        var resultsByCallIndex: [Int: MessageRecord] = [:]
        for (callIndex, call) in calls.enumerated() {
            guard let candidateIndex = candidates.indices.first(where: {
                !usedCandidateIndices.contains($0)
                    && candidates[$0].toolCallID == call.id
            }) else {
                continue
            }
            usedCandidateIndices.insert(candidateIndex)
            resultsByCallIndex[callIndex] = candidates[candidateIndex]
        }
        return resultsByCallIndex
    }

    private static func finalAssistantMessageIDs(
        in messages: [MessageRecord]
    ) -> Set<UUID> {
        var result: Set<UUID> = []
        var finalAssistantID: UUID?

        for message in messages {
            if message.role == .user {
                if let finalAssistantID {
                    result.insert(finalAssistantID)
                }
                finalAssistantID = nil
            } else if message.role == .assistant {
                finalAssistantID = message.id
            }
        }
        if let finalAssistantID {
            result.insert(finalAssistantID)
        }
        return result
    }

    private static func hasVisibleText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
