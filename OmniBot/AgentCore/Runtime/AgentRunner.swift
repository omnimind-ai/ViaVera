import Foundation

/// A tool-agnostic Agent loop. The iSH integration only needs to provide an
/// AgentToolExecuting implementation; model and persistence concerns remain separate.
public actor AgentRunner {
    private static let maximumModelToolResultBytesPerCall = 12 * 1_024
    private static let maximumModelToolResultBytesPerRun = 128 * 1_024
    private static let minimumReservedModelToolResultBytes = 192
    private static let maximumToolCallArgumentsBytes = 32 * 1_024
    private static let maximumToolCallIdentifierBytes = 512
    private static let maximumToolCallNameBytes = 256
    private static let maximumFinalAssistantMessageBytes = 512 * 1_024

    private let client: any AgentChatCompleting
    private let toolExecutor: any AgentToolExecuting
    private let maxRounds: Int
    private let maxToolCallsPerRound: Int
    private let maxToolCallsPerRun: Int
    private let retryPolicy: AgentRetryPolicy
    private var activeRuns: [UUID: Task<AgentRunResult, Error>] = [:]

    public init(
        client: any AgentChatCompleting,
        toolExecutor: any AgentToolExecuting,
        maxRounds: Int = 16,
        maxToolCallsPerRound: Int = 32,
        maxToolCallsPerRun: Int = 64,
        retryPolicy: AgentRetryPolicy = .default
    ) {
        self.client = client
        self.toolExecutor = toolExecutor
        self.maxRounds = max(1, maxRounds)
        let hardToolCallLimit = Self.maximumModelToolResultBytesPerRun
            / Self.minimumReservedModelToolResultBytes
        self.maxToolCallsPerRun = min(max(1, maxToolCallsPerRun), hardToolCallLimit)
        self.maxToolCallsPerRound = min(
            max(1, maxToolCallsPerRound),
            self.maxToolCallsPerRun
        )
        self.retryPolicy = retryPolicy
    }

    public func run(
        _ input: AgentRunInput,
        onEvent: @escaping AgentRunEventHandler = { _ in }
    ) async throws -> AgentRunResult {
        guard activeRuns[input.runID] == nil else {
            throw AgentRunnerError.duplicateRun(input.runID)
        }

        let task = Task { [self] in
            try await execute(input, onEvent: onEvent)
        }
        activeRuns[input.runID] = task
        defer { activeRuns[input.runID] = nil }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
                Task { await self.cancel(runID: input.runID) }
            }
        } catch is CancellationError {
            try? await onEvent(.cancelled(runID: input.runID))
            throw CancellationError()
        }
    }

    public func cancel(runID: UUID) async {
        guard let task = activeRuns[runID] else { return }
        task.cancel()
        await client.cancel(runID: runID)
        await toolExecutor.cancel(runID: runID)
    }

    /// Stops only the currently executing tool. The tool executor converts the
    /// interruption into a normal error result so the model can inspect it and
    /// continue the same Agent run.
    public func cancelCurrentTool(runID: UUID, callID: String) async -> Bool {
        guard activeRuns[runID] != nil else { return false }
        return await toolExecutor.cancelCurrentTool(runID: runID, callID: callID)
    }

    public static func mergeInitialMessages(
        systemMessages: [AgentMessage],
        history: [AgentMessage],
        currentUserMessage: AgentMessage,
        continueMode: Bool
    ) throws -> [AgentMessage] {
        guard currentUserMessage.role == .user else {
            throw AgentRunnerError.invalidCurrentUserMessage
        }

        var result: [AgentMessage] = []
        var seenIDs: Set<UUID> = []

        for message in systemMessages + history.filter({ $0.role == .system }) {
            guard message.role == .system, seenIDs.insert(message.id).inserted else { continue }
            result.append(message)
        }

        var uniqueHistory: [AgentMessage] = []
        for message in history where message.role != .system {
            guard seenIDs.insert(message.id).inserted else { continue }
            uniqueHistory.append(message)
        }

        for message in AgentConversationHistoryWindow.repairToolTransactions(uniqueHistory) {
            result.append(message)
        }

        let alreadyPresentByID = seenIDs.contains(currentUserMessage.id)
        let lastUser = result.last(where: { $0.role == .user })
        let alreadyPresentByContinuationContent = continueMode
            && normalized(lastUser?.content) == normalized(currentUserMessage.content)

        if !alreadyPresentByID && !alreadyPresentByContinuationContent {
            result.append(currentUserMessage)
        }
        return result
    }

    private func execute(
        _ input: AgentRunInput,
        onEvent: @escaping AgentRunEventHandler
    ) async throws -> AgentRunResult {
        try Task.checkCancellation()
        try await onEvent(.started(runID: input.runID))

        let tools = input.allowsToolCalls
            ? await toolExecutor.availableTools().sorted { $0.name < $1.name }
            : []
        let boundedHistory = AgentConversationHistoryWindow.select(
            history: input.history,
            currentUserMessage: input.currentUserMessage,
            systemMessages: input.systemMessages,
            tools: tools,
            contextWindow: input.contextWindow,
            maxOutputTokens: input.maxTokens
        )
        var messages = try Self.mergeInitialMessages(
            systemMessages: input.systemMessages,
            history: boundedHistory,
            currentUserMessage: input.currentUserMessage,
            continueMode: input.continueMode
        )
        let knownTools = Set(tools.map(\.name))
        let modelToolResultBudget = Self.modelToolResultBudget(
            contextWindow: input.contextWindow
        )
        let effectiveMaxToolCallsPerRun = min(
            maxToolCallsPerRun,
            max(1, modelToolResultBudget / Self.minimumReservedModelToolResultBytes)
        )
        var totalUsage = AgentUsage.zero
        var toolExecutionCount = 0
        var modelToolResultBytes = 0
        var modelAssistantToolBytes = 0

        for round in 1...maxRounds {
            try Task.checkCancellation()
            let intermediateBytesUsed = modelAssistantToolBytes + modelToolResultBytes
            let remainingIntermediateBytes = max(
                0,
                modelToolResultBudget - intermediateBytesUsed
            )
            let intermediateReserveTokens = (remainingIntermediateBytes + 2) / 3
            // Re-budget before every provider request. The current user turn
            // remains atomic, while older turns can be dropped after the size
            // of newly appended assistant/tool messages becomes known.
            let requestHistory = AgentConversationHistoryWindow.select(
                history: messages.filter { $0.role != .system },
                currentUserMessage: input.currentUserMessage,
                systemMessages: input.systemMessages,
                tools: tools,
                contextWindow: input.contextWindow,
                maxOutputTokens: input.maxTokens,
                additionalReserveTokens: intermediateReserveTokens
            )
            messages = try Self.mergeInitialMessages(
                systemMessages: input.systemMessages,
                history: requestHistory,
                currentUserMessage: input.currentUserMessage,
                continueMode: true
            )
            guard AgentConversationHistoryWindow.fitsContext(
                messages: messages,
                tools: tools,
                contextWindow: input.contextWindow,
                maxOutputTokens: input.maxTokens,
                additionalReserveTokens: intermediateReserveTokens
            ) else {
                throw AgentRunnerError.contextWindowTooSmall(input.contextWindow ?? 0)
            }
            let supportsStreaming = client is any AgentChatStreaming
            let request = AgentChatRequest(
                runID: input.runID,
                model: input.model,
                messages: messages,
                tools: tools,
                temperature: input.temperature,
                maxTokens: input.maxTokens,
                reasoningEffort: input.reasoningEffort,
                promptCacheKey: AgentChatRequest.promptCacheKey(
                    conversationID: input.conversationID
                ),
                stream: supportsStreaming
            )
            let assistantMessageID = UUID()
            let response = try await completeWithRetry(
                request,
                apiKey: input.apiKey,
                round: round,
                assistantMessageID: assistantMessageID,
                onEvent: onEvent
            )
            try Task.checkCancellation()

            let normalizedFinishReason = response.finishReason?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let hasTruncatedToolCalls = Self.isLengthFinishReason(
                normalizedFinishReason
            ) && !response.message.toolCalls.isEmpty
            switch normalizedFinishReason {
            case let reason where Self.isLengthFinishReason(reason)
                && !hasTruncatedToolCalls:
                throw AgentRunnerError.outputTruncated
            case "content_filter", "content-filter":
                throw AgentRunnerError.contentFiltered
            default:
                break
            }

            let assistant = AgentMessage(
                id: assistantMessageID,
                role: response.message.role,
                content: response.message.content,
                reasoningContent: response.message.reasoningContent,
                providerMetadata: response.message.providerMetadata,
                toolCalls: response.message.toolCalls,
                toolCallID: response.message.toolCallID,
                name: response.message.name
            )
            guard assistant.role == .assistant,
                  !Self.normalized(assistant.content).isEmpty
                    || !Self.normalized(assistant.reasoningContent).isEmpty
                    || !assistant.toolCalls.isEmpty else {
                throw AgentRunnerError.emptyAssistantResponse
            }

            if !assistant.toolCalls.isEmpty {
                // Count/identifier checks are cheap and run before re-encoding
                // any provider-controlled tool payload.
                try validateToolCalls(
                    assistant.toolCalls,
                    alreadyExecuted: toolExecutionCount,
                    maximumPerRun: effectiveMaxToolCallsPerRun
                )
            }
            let encodedAssistantBytes = try validateAssistantMessage(
                assistant,
                contextWindow: input.contextWindow
            )

            if !assistant.toolCalls.isEmpty {
                let intermediateBytesUsed = modelAssistantToolBytes + modelToolResultBytes
                guard intermediateBytesUsed <= modelToolResultBudget - encodedAssistantBytes else {
                    throw AgentRunnerError.assistantToolContextBudgetExceeded(
                        modelToolResultBudget
                    )
                }
                try validateToolResultCapacity(
                    callCount: assistant.toolCalls.count,
                    bytesAlreadyUsed: intermediateBytesUsed + encodedAssistantBytes,
                    maximumBytes: modelToolResultBudget
                )
            }

            messages.append(assistant)
            if !assistant.toolCalls.isEmpty {
                modelAssistantToolBytes += encodedAssistantBytes
            }
            totalUsage = totalUsage + response.usage
            try await onEvent(.assistantMessage(
                assistant,
                usage: response.usage,
                contextWindow: input.contextWindow,
                round: round
            ))

            if assistant.toolCalls.isEmpty {
                let result = AgentRunResult(
                    runID: input.runID,
                    finalMessage: assistant,
                    messages: messages,
                    usage: totalUsage,
                    rounds: round,
                    toolExecutionCount: toolExecutionCount
                )
                try await onEvent(.completed(result))
                return result
            }

            guard round < maxRounds else {
                throw AgentRunnerError.maximumRoundsExceeded(maxRounds)
            }

            if hasTruncatedToolCalls {
                for (callIndex, call) in assistant.toolCalls.enumerated() {
                    try Task.checkCancellation()
                    try await onEvent(.toolStarted(call, round: round))
                    let rejected = AgentToolExecutionResult(
                        content: "This tool call was not executed because the model output reached its length limit and the arguments may be truncated. Re-issue it in the next round with complete arguments.",
                        isError: true,
                        metadata: [
                            "reason": .string("truncated_model_output"),
                            "finishReason": .string(normalizedFinishReason ?? "length"),
                        ]
                    )
                    let modelByteLimit = modelToolResultByteLimit(
                        bytesAlreadyUsed: modelAssistantToolBytes + modelToolResultBytes,
                        callsRemainingInTurn: assistant.toolCalls.count - callIndex - 1,
                        maximumBytes: modelToolResultBudget
                    )
                    let boundedResult = try boundedToolResult(
                        rejected,
                        maximumModelUTF8Bytes: modelByteLimit
                    )
                    modelToolResultBytes += boundedResult.modelContent.utf8.count
                    try await onEvent(.toolCompleted(
                        call,
                        result: boundedResult.result,
                        round: round
                    ))
                    messages.append(.tool(
                        callID: call.id,
                        name: call.name,
                        content: boundedResult.modelContent
                    ))
                }
                continue
            }

            let context = AgentToolExecutionContext(
                runID: input.runID,
                conversationID: input.conversationID,
                workspaceURL: input.workspaceURL
            )

            for (callIndex, call) in assistant.toolCalls.enumerated() {
                try Task.checkCancellation()
                try await onEvent(.toolStarted(call, round: round))

                let result: AgentToolExecutionResult
                if !knownTools.contains(call.name) {
                    result = AgentToolExecutionResult(
                        content: "Unknown tool: \(call.name)",
                        isError: true
                    )
                } else {
                    do {
                        result = try await toolExecutor.execute(call, context: context)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        result = AgentToolExecutionResult(
                            content: error.localizedDescription,
                            isError: true
                        )
                    }
                }

                let modelByteLimit = modelToolResultByteLimit(
                    bytesAlreadyUsed: modelAssistantToolBytes + modelToolResultBytes,
                    callsRemainingInTurn: assistant.toolCalls.count - callIndex - 1,
                    maximumBytes: modelToolResultBudget
                )
                let boundedResult = try boundedToolResult(
                    result,
                    maximumModelUTF8Bytes: modelByteLimit
                )
                toolExecutionCount += 1
                modelToolResultBytes += boundedResult.modelContent.utf8.count
                try await onEvent(.toolCompleted(
                    call,
                    result: boundedResult.result,
                    round: round
                ))
                messages.append(.tool(
                    callID: call.id,
                    name: call.name,
                    content: boundedResult.modelContent
                ))
            }
        }

        throw AgentRunnerError.maximumRoundsExceeded(maxRounds)
    }

    /// Rejects the entire model turn before it is persisted or any tool gains
    /// side effects. Executing only a prefix would leave an invalid tool-call
    /// transaction and still let a hostile response perform partial work.
    private func validateToolCalls(
        _ calls: [AgentToolCall],
        alreadyExecuted: Int,
        maximumPerRun: Int
    ) throws {
        let maximumPerRound = min(maxToolCallsPerRound, maximumPerRun)
        guard calls.count <= maximumPerRound else {
            throw AgentRunnerError.maximumToolCallsPerRoundExceeded(
                maximum: maximumPerRound,
                received: calls.count
            )
        }
        guard alreadyExecuted <= maximumPerRun - calls.count else {
            throw AgentRunnerError.maximumToolCallsPerRunExceeded(maximumPerRun)
        }

        var identifiers = Set<String>()
        guard calls.allSatisfy({ !$0.id.isEmpty && identifiers.insert($0.id).inserted }) else {
            throw AgentRunnerError.invalidToolCallIdentifiers
        }
    }

    @discardableResult
    private func validateAssistantMessage(
        _ assistant: AgentMessage,
        contextWindow: Int?
    ) throws -> Int {
        let intermediateBudget = Self.modelToolResultBudget(
            contextWindow: contextWindow
        )
        let argumentLimit = min(
            Self.maximumToolCallArgumentsBytes,
            max(Self.maximumToolCallIdentifierBytes, intermediateBudget / 2)
        )
        for call in assistant.toolCalls {
            guard call.id.utf8.count <= Self.maximumToolCallIdentifierBytes else {
                throw AgentRunnerError.toolCallFieldTooLarge(
                    "identifier",
                    maximumBytes: Self.maximumToolCallIdentifierBytes
                )
            }
            guard call.name.utf8.count <= Self.maximumToolCallNameBytes else {
                throw AgentRunnerError.toolCallFieldTooLarge(
                    "name",
                    maximumBytes: Self.maximumToolCallNameBytes
                )
            }
            guard call.arguments.utf8.count <= argumentLimit else {
                throw AgentRunnerError.toolCallFieldTooLarge(
                    "arguments",
                    maximumBytes: argumentLimit
                )
            }
        }

        let encodedBytes = try JSONEncoder().encode(assistant).count
        if !assistant.toolCalls.isEmpty {
            guard encodedBytes <= intermediateBudget else {
                throw AgentRunnerError.assistantToolContextBudgetExceeded(
                    intermediateBudget
                )
            }
            return encodedBytes
        }

        let finalBudget: Int
        if let contextWindow, contextWindow > 0 {
            let scaled = (contextWindow / 2).multipliedReportingOverflow(by: 3)
            finalBudget = min(
                Self.maximumFinalAssistantMessageBytes,
                max(
                    Self.minimumReservedModelToolResultBytes,
                    scaled.overflow ? Self.maximumFinalAssistantMessageBytes : scaled.partialValue
                )
            )
        } else {
            finalBudget = Self.maximumFinalAssistantMessageBytes
        }
        guard encodedBytes <= finalBudget else {
            throw AgentRunnerError.assistantMessageTooLarge(finalBudget)
        }
        return encodedBytes
    }

    private func validateToolResultCapacity(
        callCount: Int,
        bytesAlreadyUsed: Int,
        maximumBytes: Int
    ) throws {
        let minimumRequired = callCount * Self.minimumReservedModelToolResultBytes
        guard bytesAlreadyUsed <= maximumBytes - minimumRequired else {
            throw AgentRunnerError.modelToolResultBudgetExceeded(maximumBytes)
        }
    }

    private func modelToolResultByteLimit(
        bytesAlreadyUsed: Int,
        callsRemainingInTurn: Int,
        maximumBytes: Int
    ) -> Int {
        let remainingBudget = max(
            0,
            maximumBytes - bytesAlreadyUsed
        )
        let futureReserve = min(
            remainingBudget,
            callsRemainingInTurn * Self.minimumReservedModelToolResultBytes
        )
        let available = max(
            Self.minimumReservedModelToolResultBytes,
            remainingBudget - futureReserve
        )
        return min(Self.maximumModelToolResultBytesPerCall, available)
    }

    private static func modelToolResultBudget(contextWindow: Int?) -> Int {
        guard let contextWindow, contextWindow > 0 else {
            return maximumModelToolResultBytesPerRun
        }
        let approximateBytes = (contextWindow / 4).multipliedReportingOverflow(by: 3)
        let scaled = approximateBytes.overflow
            ? maximumModelToolResultBytesPerRun
            : approximateBytes.partialValue
        return min(
            maximumModelToolResultBytesPerRun,
            max(minimumReservedModelToolResultBytes, scaled)
        )
    }

    /// Bounds the exact JSON string sent back to the model, not only the raw
    /// tool content. JSON escaping and metadata can otherwise turn an already
    /// large result into a much larger next-round request.
    private func boundedToolResult(
        _ result: AgentToolExecutionResult,
        maximumModelUTF8Bytes: Int
    ) throws -> (result: AgentToolExecutionResult, modelContent: String) {
        let fullContent = try result.modelContent()
        guard fullContent.utf8.count > maximumModelUTF8Bytes else {
            return (result, fullContent)
        }

        let marker = "\n[Tool output truncated to fit the Agent context.]"
        var metadata: [String: AgentValue] = [
            "modelOutputTruncated": .bool(true),
            "originalContentUTF8Bytes": .number(Double(result.content.utf8.count)),
        ]
        let metadataBudget = min(8 * 1_024, maximumModelUTF8Bytes / 4)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for key in result.metadata.keys.sorted() where key.utf8.count <= 128 {
            guard let value = result.metadata[key] else { continue }
            var candidate = metadata
            candidate[key] = value
            let encodedSize = try encoder.encode(AgentValue.object(candidate)).count
            if encodedSize <= metadataBudget {
                metadata = candidate
            }
        }

        // Artifacts are the durable hand-off for files created by tools. Keep
        // them when trimming verbose stdout/content; dropping them here makes
        // a successful file-producing tool impossible for the model to cite.
        var retainedArtifacts = result.artifacts
        var retainedActions = result.actions
        while retainedArtifacts.count > 1 {
            let candidate = AgentToolExecutionResult(
                content: marker,
                isError: result.isError,
                metadata: metadata,
                artifacts: retainedArtifacts,
                workspaceID: result.workspaceID,
                actions: retainedActions
            )
            guard try candidate.modelContent().utf8.count > maximumModelUTF8Bytes else {
                break
            }
            retainedArtifacts.removeLast()
        }
        while !retainedActions.isEmpty {
            let candidate = AgentToolExecutionResult(
                content: marker,
                isError: result.isError,
                metadata: metadata,
                artifacts: retainedArtifacts,
                workspaceID: result.workspaceID,
                actions: retainedActions
            )
            guard try candidate.modelContent().utf8.count > maximumModelUTF8Bytes else {
                break
            }
            retainedActions.removeLast()
        }
        if retainedArtifacts.count < result.artifacts.count {
            metadata["artifactsTruncated"] = .bool(true)
            metadata["originalArtifactCount"] = .number(Double(result.artifacts.count))
        }
        if retainedActions.count < result.actions.count {
            metadata["actionsTruncated"] = .bool(true)
            metadata["originalActionCount"] = .number(Double(result.actions.count))
        }

        var lower = 0
        var upper = result.content.utf8.count
        var best: (AgentToolExecutionResult, String)?
        while lower <= upper {
            let midpoint = lower + (upper - lower) / 2
            let excerpt = Self.utf8HeadTail(result.content, maximumBytes: midpoint)
            let candidate = AgentToolExecutionResult(
                content: excerpt + marker,
                isError: result.isError,
                metadata: metadata,
                artifacts: retainedArtifacts,
                workspaceID: result.workspaceID,
                actions: retainedActions
            )
            let encoded = try candidate.modelContent()
            if encoded.utf8.count <= maximumModelUTF8Bytes {
                best = (candidate, encoded)
                lower = midpoint + 1
            } else {
                upper = midpoint - 1
            }
        }
        if let best {
            return best
        }

        // The fixed fallback is deliberately tiny enough for the reserved
        // per-call envelope even when the original metadata itself was huge.
        let fallback = AgentToolExecutionResult(
            content: "Tool output omitted: the Agent context budget is exhausted.",
            isError: true
        )
        let encodedFallback = try fallback.modelContent()
        guard encodedFallback.utf8.count <= maximumModelUTF8Bytes else {
            // The configured limits reserve 256 bytes, so this is defensive.
            return (fallback, "{}")
        }
        return (fallback, encodedFallback)
    }

    private static func utf8Prefix(_ value: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        return String(decoding: value.utf8.prefix(maximumBytes), as: UTF8.self)
    }

    private static func isLengthFinishReason(_ value: String?) -> Bool {
        switch value {
        case "length", "max_tokens", "max_completion_tokens", "max_output_tokens":
            true
        default:
            false
        }
    }

    /// Retains both the start (usually the command/result summary) and the end
    /// (usually the error or completion state), matching the compact tool-result
    /// envelope used by the Android harness.
    private static func utf8HeadTail(_ value: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        guard value.utf8.count > maximumBytes else { return value }
        let separator = "\n...[middle of tool output omitted]...\n"
        let separatorBytes = separator.utf8.count
        guard maximumBytes > separatorBytes else {
            return utf8Prefix(value, maximumBytes: maximumBytes)
        }
        let contentBudget = maximumBytes - separatorBytes
        let headBytes = (contentBudget + 1) / 2
        let tailBytes = contentBudget / 2
        let head = String(decoding: value.utf8.prefix(headBytes), as: UTF8.self)
        let tail = String(decoding: value.utf8.suffix(tailBytes), as: UTF8.self)
        return head + separator + tail
    }

    private func completeWithRetry(
        _ request: AgentChatRequest,
        apiKey: String,
        round: Int,
        assistantMessageID: UUID,
        onEvent: @escaping AgentRunEventHandler
    ) async throws -> AgentChatResponse {
        var lastError: (any Error)?

        for attempt in 1...retryPolicy.maxAttempts {
            try Task.checkCancellation()
            try await onEvent(.requestStarted(round: round, attempt: attempt))
            do {
                // The same immutable request is retried, so its current user turn cannot disappear.
                if let streamingClient = client as? any AgentChatStreaming {
                    try await onEvent(.assistantMessageStarted(
                        id: assistantMessageID,
                        round: round
                    ))
                    let coalescer = AgentStreamSnapshotCoalescer { snapshot in
                        try await onEvent(.assistantMessageUpdated(
                            id: assistantMessageID,
                            snapshot: snapshot,
                            round: round
                        ))
                    }
                    do {
                        let response = try await streamingClient.stream(
                            request,
                            apiKey: apiKey
                        ) { snapshot in
                            try await coalescer.consume(snapshot)
                        }
                        try await coalescer.flush()
                        return response
                    } catch {
                        try? await coalescer.flush()
                        throw error
                    }
                }
                return try await client.complete(request, apiKey: apiKey)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let retryable = (error as? any AgentRetryClassifying)?.isRetryable ?? true
                guard retryable, attempt < retryPolicy.maxAttempts else { throw error }

                try await onEvent(.retrying(
                    round: round,
                    nextAttempt: attempt + 1,
                    errorDescription: error.localizedDescription
                ))
                let delay = retryPolicy.delayNanoseconds(beforeAttempt: attempt + 1)
                if delay > 0 {
                    let clampedDelay = Int64(min(delay, UInt64(Int64.max)))
                    try await Task.sleep(for: .nanoseconds(clampedDelay))
                }
            }
        }

        throw lastError ?? AgentRunnerError.emptyAssistantResponse
    }

    private static func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            ?? ""
    }
}
