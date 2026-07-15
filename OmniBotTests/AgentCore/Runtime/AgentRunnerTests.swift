import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent runner")
struct AgentRunnerTests {
    @Test("Models without tool support receive no tool schemas")
    func modelWithoutToolSupportReceivesNoTools() async throws {
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant("No tools requested")),
        ])
        let runner = AgentRunner(
            client: client,
            toolExecutor: RecordingToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let base = makeInput(currentUserMessage: .user("Answer directly"))
        let input = AgentRunInput(
            runID: base.runID,
            conversationID: base.conversationID,
            model: base.model,
            apiKey: base.apiKey,
            systemMessages: base.systemMessages,
            history: base.history,
            currentUserMessage: base.currentUserMessage,
            workspaceURL: base.workspaceURL,
            allowsToolCalls: false
        )

        _ = try await runner.run(input)

        let requests = await client.requests()
        #expect(requests.count == 1)
        #expect(requests[0].tools.isEmpty)
    }

    @Test("Executes tool calls, feeds role=tool results back, and finishes")
    func toolLoop() async throws {
        let call = AgentToolCall(
            id: "call_terminal",
            name: "terminal_execute",
            arguments: #"{"command":"pwd"}"#
        )
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant(toolCalls: [call])),
            AgentChatResponse(
                message: .assistant("The workspace is /workspace."),
                usage: AgentUsage(promptTokens: 10, completionTokens: 4, totalTokens: 14)
            ),
        ])
        let tools = RecordingToolExecutor()
        let runner = AgentRunner(
            client: client,
            toolExecutor: tools,
            maxRounds: 4,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let input = makeInput(currentUserMessage: .user("Where am I?"))

        let result = try await runner.run(input)

        #expect(result.finalMessage.content == "The workspace is /workspace.")
        #expect(result.toolExecutionCount == 1)
        #expect(await tools.calls().map(\.id) == [call.id])

        let requests = await client.requests()
        #expect(requests.count == 2)
        #expect(requests[1].messages.map(\.role) == [.system, .user, .assistant, .tool])
        #expect(requests[1].messages.last?.toolCallID == call.id)
        #expect(requests[1].messages.last?.content?.contains("/workspace") == true)
    }

    @Test("Multi-round token usage saturates instead of overflowing")
    func multiRoundUsageSaturates() async throws {
        let call = AgentToolCall(
            id: "call_usage",
            name: "terminal_execute",
            arguments: #"{"command":"pwd"}"#
        )
        let maximumUsage = AgentUsage(
            promptTokens: .max,
            completionTokens: .max,
            totalTokens: .max
        )
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(
                message: .assistant(toolCalls: [call]),
                usage: maximumUsage
            ),
            AgentChatResponse(
                message: .assistant("Done"),
                usage: AgentUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2)
            ),
        ])
        let runner = AgentRunner(
            client: client,
            toolExecutor: RecordingToolExecutor(),
            maxRounds: 3,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        let result = try await runner.run(
            makeInput(currentUserMessage: .user("Exercise multiple rounds"))
        )

        #expect(result.usage.promptTokens == .max)
        #expect(result.usage.completionTokens == .max)
        #expect(result.usage.totalTokens == .max)
    }

    @Test("Continue merge never loses or duplicates the current user turn")
    func continueMerge() throws {
        let current = AgentMessage.user("Continue the failed task")
        let system = AgentMessage.system("System")

        let missingHistory = try AgentRunner.mergeInitialMessages(
            systemMessages: [system],
            history: [],
            currentUserMessage: current,
            continueMode: true
        )
        #expect(missingHistory.last == current)

        let existingHistory = try AgentRunner.mergeInitialMessages(
            systemMessages: [system],
            history: [current, .assistant("A failed partial response")],
            currentUserMessage: current,
            continueMode: true
        )
        #expect(existingHistory.filter { $0.id == current.id }.count == 1)

        let reconstructedCurrent = AgentMessage.user("Continue the failed task")
        let reconstructedHistory = try AgentRunner.mergeInitialMessages(
            systemMessages: [system],
            history: [current, .assistant("A failed partial response")],
            currentUserMessage: reconstructedCurrent,
            continueMode: true
        )
        #expect(reconstructedHistory.filter {
            $0.role == .user && $0.content == current.content
        }.count == 1)
    }

    @Test("Incomplete tool-call history is repaired and orphan tool results are removed")
    func repairsIncompleteToolTransactions() throws {
        let firstCall = AgentToolCall(id: "call_one", name: "first", arguments: "{}")
        let secondCall = AgentToolCall(id: "call_two", name: "second", arguments: "{}")
        let current = AgentMessage.user("Continue")

        let merged = try AgentRunner.mergeInitialMessages(
            systemMessages: [.system("System")],
            history: [
                .user("Original task"),
                .assistant(toolCalls: [firstCall, secondCall]),
                .tool(callID: firstCall.id, name: firstCall.name, content: "first result"),
                .tool(callID: "orphan", name: "orphan", content: "must disappear"),
                current,
                .tool(callID: "standalone", name: "orphan", content: "must disappear"),
            ],
            currentUserMessage: current,
            continueMode: true
        )

        let tools = merged.filter { $0.role == .tool }
        #expect(tools.map(\.toolCallID) == [firstCall.id, secondCall.id])
        #expect(tools[0].content == "first result")
        #expect(tools[1].content?.contains(#""outcome":"unknown""#) == true)
        #expect(tools[1].content?.contains("action may have completed") == true)
        #expect(tools[1].content?.contains("never blindly repeat") == true)
        #expect(!merged.contains(where: { $0.content == "must disappear" }))
    }

    @Test("History window keeps the current turn and complete tool transactions")
    func boundedHistoryKeepsAtomicCurrentTurn() {
        let oldUser = AgentMessage.user(String(repeating: "old context ", count: 2_000))
        let current = AgentMessage.user("current task")
        let call = AgentToolCall(id: "pending", name: "terminal_execute", arguments: #"{"command":"pwd"}"#)
        let history: [AgentMessage] = [
            oldUser,
            .assistant("old answer"),
            current,
            .assistant(toolCalls: [call]),
        ]
        let tools = [AgentToolDefinition(
            name: "terminal_execute",
            description: String(repeating: "tool schema ", count: 200),
            parameters: .object(["type": .string("object")])
        )]

        let selected = AgentConversationHistoryWindow.select(
            history: history,
            currentUserMessage: current,
            systemMessages: [.system(String(repeating: "system ", count: 100))],
            tools: tools,
            contextWindow: 1_200,
            maxOutputTokens: 300
        )

        #expect(!selected.contains(where: { $0.id == oldUser.id }))
        #expect(selected.first?.id == current.id)
        #expect(selected.map(\.role) == [.user, .assistant, .tool])
        #expect(selected.last?.toolCallID == call.id)
    }

    @Test("Current user is retained even when it alone exceeds the context budget")
    func currentUserAlwaysRetained() {
        let current = AgentMessage.user(String(repeating: "large prompt ", count: 500))
        let selected = AgentConversationHistoryWindow.select(
            history: [],
            currentUserMessage: current,
            systemMessages: [.system("System")],
            tools: [],
            contextWindow: 128,
            maxOutputTokens: 64
        )

        #expect(selected == [current])
    }

    @Test("A retry reuses the exact request including the current user message")
    func retryPreservesPrompt() async throws {
        let current = AgentMessage.user("Do not lose this prompt")
        let client = ScriptedChatClient(
            responses: [AgentChatResponse(message: .assistant("Done"))],
            transientFailures: 1
        )
        let runner = AgentRunner(
            client: client,
            toolExecutor: RecordingToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 2, initialDelayNanoseconds: 0)
        )

        _ = try await runner.run(makeInput(currentUserMessage: current))
        let requests = await client.requests()

        #expect(requests.count == 2)
        #expect(requests[0].messages == requests[1].messages)
        #expect(requests.allSatisfy { request in
            request.messages.contains(where: { $0.id == current.id })
        })
    }

    @Test("Cancelling a run propagates to the model client")
    func cancellation() async throws {
        let runID = UUID()
        let client = BlockingChatClient()
        let runner = AgentRunner(
            client: client,
            toolExecutor: RecordingToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let base = makeInput(currentUserMessage: .user("Wait"))
        let input = AgentRunInput(
            runID: runID,
            conversationID: base.conversationID,
            model: base.model,
            apiKey: base.apiKey,
            systemMessages: base.systemMessages,
            history: base.history,
            currentUserMessage: base.currentUserMessage,
            workspaceURL: base.workspaceURL
        )

        let task = Task { try await runner.run(input) }
        try await Task.sleep(nanoseconds: 30_000_000)
        await runner.cancel(runID: runID)

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        #expect(await client.cancelledRunIDs().contains(runID))
    }

    @Test("Stopping the current tool lets the Agent continue its run")
    func currentToolCancellationContinuesRun() async throws {
        let runID = UUID()
        let call = AgentToolCall(
            id: "call_stop",
            name: "terminal_execute",
            arguments: #"{"command":"sleep 30"}"#
        )
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant(toolCalls: [call])),
            AgentChatResponse(message: .assistant("Continued after the stopped tool")),
        ])
        let executor = StoppableToolExecutor()
        let runner = AgentRunner(
            client: client,
            toolExecutor: executor,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let base = makeInput(currentUserMessage: .user("Run a command"))
        let input = AgentRunInput(
            runID: runID,
            conversationID: base.conversationID,
            model: base.model,
            apiKey: base.apiKey,
            systemMessages: base.systemMessages,
            history: base.history,
            currentUserMessage: base.currentUserMessage,
            workspaceURL: base.workspaceURL
        )

        let task = Task { try await runner.run(input) }
        for _ in 0..<1_000 {
            if await executor.hasStarted() { break }
            await Task.yield()
        }
        #expect(await executor.hasStarted())

        #expect(await runner.cancelCurrentTool(runID: runID, callID: call.id))
        let result = try await task.value

        #expect(result.finalMessage.content == "Continued after the stopped tool")
        let requests = await client.requests()
        #expect(requests.count == 2)
        #expect(requests[1].messages.contains { message in
            message.role == .tool && message.content?.contains("stopped by user") == true
        })
    }

    @Test("Persistence event failures terminate the run")
    func eventFailureTerminatesRun() async throws {
        let runner = AgentRunner(
            client: ScriptedChatClient(responses: [
                AgentChatResponse(message: .assistant("Done")),
            ]),
            toolExecutor: RecordingToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        await #expect(throws: EventHandlerError.saveFailed) {
            try await runner.run(makeInput(currentUserMessage: .user("Run"))) { event in
                if case .assistantMessage = event {
                    throw EventHandlerError.saveFailed
                }
            }
        }
    }

    @Test("An oversized tool-call turn is rejected before any side effect")
    func oversizedToolTurnIsAtomic() async throws {
        let calls = (0..<5).map { index in
            AgentToolCall(
                id: "call_\(index)",
                name: "terminal_execute",
                arguments: #"{"command":"true"}"#
            )
        }
        let tools = RecordingToolExecutor()
        let runner = AgentRunner(
            client: ScriptedChatClient(responses: [
                AgentChatResponse(message: .assistant(toolCalls: calls)),
            ]),
            toolExecutor: tools,
            maxToolCallsPerRound: 4,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        await #expect(throws: AgentRunnerError.maximumToolCallsPerRoundExceeded(
            maximum: 4,
            received: 5
        )) {
            try await runner.run(makeInput(currentUserMessage: .user("Run everything")))
        }
        #expect(await tools.calls().isEmpty)
    }

    @Test("The whole-run tool-call budget is checked before the next turn")
    func wholeRunToolBudgetIsAtomic() async throws {
        let first = (0..<2).map { index in
            AgentToolCall(
                id: "first_\(index)",
                name: "terminal_execute",
                arguments: #"{"command":"true"}"#
            )
        }
        let second = (0..<2).map { index in
            AgentToolCall(
                id: "second_\(index)",
                name: "terminal_execute",
                arguments: #"{"command":"true"}"#
            )
        }
        let tools = RecordingToolExecutor()
        let runner = AgentRunner(
            client: ScriptedChatClient(responses: [
                AgentChatResponse(message: .assistant(toolCalls: first)),
                AgentChatResponse(message: .assistant(toolCalls: second)),
            ]),
            toolExecutor: tools,
            maxRounds: 4,
            maxToolCallsPerRound: 2,
            maxToolCallsPerRun: 3,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        await #expect(throws: AgentRunnerError.maximumToolCallsPerRunExceeded(3)) {
            try await runner.run(makeInput(currentUserMessage: .user("Run")))
        }
        #expect(await tools.calls().map(\.id) == first.map(\.id))
    }

    @Test("Empty or duplicate tool-call IDs are rejected before execution")
    func invalidToolCallIdentifiersAreAtomic() async throws {
        let calls = [
            AgentToolCall(id: "duplicate", name: "terminal_execute", arguments: "{}"),
            AgentToolCall(id: "duplicate", name: "terminal_execute", arguments: "{}"),
        ]
        let tools = RecordingToolExecutor()
        let runner = AgentRunner(
            client: ScriptedChatClient(responses: [
                AgentChatResponse(message: .assistant(toolCalls: calls)),
            ]),
            toolExecutor: tools,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        await #expect(throws: AgentRunnerError.invalidToolCallIdentifiers) {
            try await runner.run(makeInput(currentUserMessage: .user("Run")))
        }
        #expect(await tools.calls().isEmpty)
    }

    @Test("Large tool results are bounded before persistence and the next model request")
    func largeToolResultsAreBounded() async throws {
        let call = AgentToolCall(
            id: "large_result",
            name: "terminal_execute",
            arguments: #"{"command":"large"}"#
        )
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant(toolCalls: [call])),
            AgentChatResponse(message: .assistant("Done")),
        ])
        let tools = RecordingToolExecutor(
            resultContent: String(repeating: "large-output\\\"\n", count: 180_000)
        )
        let runner = AgentRunner(
            client: client,
            toolExecutor: tools,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        _ = try await runner.run(makeInput(currentUserMessage: .user("Read it")))

        let requests = await client.requests()
        let toolMessage = try #require(requests.last?.messages.last(where: { $0.role == .tool }))
        let modelContent = try #require(toolMessage.content)
        #expect(modelContent.utf8.count <= 32 * 1_024)
        #expect(modelContent.contains("modelOutputTruncated"))
        #expect(modelContent.contains("Tool output truncated"))
    }

    @Test("Bounding verbose tool output preserves its artifact hand-off")
    func boundedToolResultPreservesArtifact() async throws {
        let call = AgentToolCall(
            id: "artifact_result",
            name: "terminal_execute",
            arguments: #"{"command":"large"}"#
        )
        let artifact = AgentArtifact(
            id: "omnibot://workspace/report.txt",
            uri: "omnibot://workspace/report.txt",
            title: "report.txt",
            fileName: "report.txt",
            mimeType: "text/plain",
            size: 42,
            sourceTool: "terminal_execute",
            workspacePath: "/workspace/report.txt",
            hostPath: "/private/workspace/report.txt",
            previewKind: "text"
        )
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant(toolCalls: [call])),
            AgentChatResponse(message: .assistant("Done")),
        ])
        let runner = AgentRunner(
            client: client,
            toolExecutor: RecordingToolExecutor(
                resultContent: String(repeating: "verbose ", count: 100_000),
                artifacts: [artifact]
            ),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        _ = try await runner.run(makeInput(currentUserMessage: .user("Create it")))

        let requests = await client.requests()
        let content = try #require(
            requests.last?.messages.last(where: { $0.role == .tool })?.content
        )
        #expect(content.contains("omnibot://workspace/report.txt"))
        #expect(!content.contains("/private/workspace/report.txt"))
    }

    @Test("Cumulative model-facing tool results stay within the run budget")
    func cumulativeToolResultsAreBounded() async throws {
        let calls = (0..<8).map { index in
            AgentToolCall(
                id: "large_\(index)",
                name: "terminal_execute",
                arguments: "{}"
            )
        }
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant(toolCalls: calls)),
            AgentChatResponse(message: .assistant("Done")),
        ])
        let tools = RecordingToolExecutor(
            resultContent: String(repeating: "x", count: 256 * 1_024)
        )
        let runner = AgentRunner(
            client: client,
            toolExecutor: tools,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        _ = try await runner.run(makeInput(currentUserMessage: .user("Run")))

        let secondRequest = try #require((await client.requests()).last)
        let totalToolBytes = secondRequest.messages
            .filter { $0.role == .tool }
            .reduce(0) { $0 + ($1.content?.utf8.count ?? 0) }
        #expect(totalToolBytes <= 128 * 1_024)
        #expect(await tools.calls().count == calls.count)
    }

    @Test("Tool-result budget scales down for a small model context window")
    func toolResultBudgetUsesContextWindow() async throws {
        let call = AgentToolCall(
            id: "small_context",
            name: "terminal_execute",
            arguments: "{}"
        )
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant(toolCalls: [call])),
            AgentChatResponse(message: .assistant("Done")),
        ])
        let runner = AgentRunner(
            client: client,
            toolExecutor: RecordingToolExecutor(
                resultContent: String(repeating: "x", count: 128 * 1_024)
            ),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let base = makeInput(currentUserMessage: .user("Run"))
        let input = AgentRunInput(
            runID: base.runID,
            conversationID: base.conversationID,
            model: base.model,
            apiKey: base.apiKey,
            systemMessages: base.systemMessages,
            history: base.history,
            currentUserMessage: base.currentUserMessage,
            workspaceURL: base.workspaceURL,
            contextWindow: 8_192
        )

        _ = try await runner.run(input)

        let secondRequest = try #require((await client.requests()).last)
        let totalToolBytes = secondRequest.messages
            .filter { $0.role == .tool }
            .reduce(0) { $0 + ($1.content?.utf8.count ?? 0) }
        #expect(totalToolBytes <= 6_144)
    }

    @Test("Intermediate context reserve drops near-full old history before tool execution")
    func intermediateReserveBoundsHistory() async throws {
        let oldUser = AgentMessage.user(String(repeating: "old-context ", count: 900))
        let call = AgentToolCall(
            id: "context_result",
            name: "terminal_execute",
            arguments: "{}"
        )
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant(toolCalls: [call])),
            AgentChatResponse(message: .assistant("Done")),
        ])
        let runner = AgentRunner(
            client: client,
            toolExecutor: RecordingToolExecutor(
                resultContent: String(repeating: "result ", count: 2_000)
            ),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let current = AgentMessage.user("Current task")
        let input = AgentRunInput(
            conversationID: UUID(),
            model: "test-model",
            apiKey: "test-key",
            systemMessages: [.system("System")],
            history: [oldUser, .assistant("Old answer")],
            currentUserMessage: current,
            workspaceURL: FileManager.default.temporaryDirectory,
            maxTokens: 2_048,
            contextWindow: 8_192
        )

        _ = try await runner.run(input)

        let requests = await client.requests()
        #expect(requests.allSatisfy { request in
            !request.messages.contains(where: { $0.id == oldUser.id })
        })
        #expect(requests.last?.messages.contains(where: { $0.id == current.id }) == true)
    }

    @Test("Oversized tool arguments are rejected before persistence or execution")
    func oversizedToolArgumentsAreAtomic() async throws {
        let call = AgentToolCall(
            id: "oversized_arguments",
            name: "terminal_execute",
            arguments: String(repeating: "x", count: 100 * 1_024)
        )
        let tools = RecordingToolExecutor()
        let runner = AgentRunner(
            client: ScriptedChatClient(responses: [
                AgentChatResponse(message: .assistant(toolCalls: [call])),
            ]),
            toolExecutor: tools,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let base = makeInput(currentUserMessage: .user("Run"))
        let input = AgentRunInput(
            runID: base.runID,
            conversationID: base.conversationID,
            model: base.model,
            apiKey: base.apiKey,
            systemMessages: base.systemMessages,
            history: base.history,
            currentUserMessage: base.currentUserMessage,
            workspaceURL: base.workspaceURL,
            contextWindow: 8_192
        )

        await #expect(throws: AgentRunnerError.toolCallFieldTooLarge(
            "arguments",
            maximumBytes: 3_072
        )) {
            try await runner.run(input)
        }
        #expect(await tools.calls().isEmpty)
    }

    @Test("A context smaller than fixed Agent input fails before transport")
    func tooSmallContextFailsBeforeTransport() async throws {
        let client = ScriptedChatClient(responses: [
            AgentChatResponse(message: .assistant("Must not be requested")),
        ])
        let runner = AgentRunner(
            client: client,
            toolExecutor: FullSchemaToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )
        let input = AgentRunInput(
            conversationID: UUID(),
            model: "test-model",
            apiKey: "test-key",
            systemMessages: [.system(String(repeating: "soul memory policy ", count: 2_000))],
            history: [],
            currentUserMessage: .user("Run"),
            workspaceURL: FileManager.default.temporaryDirectory,
            maxTokens: 2_048,
            contextWindow: 8_192
        )

        await #expect(throws: AgentRunnerError.contextWindowTooSmall(8_192)) {
            try await runner.run(input)
        }
        #expect(await client.requests().isEmpty)
    }

    @Test(arguments: [
        ("length", AgentRunnerError.outputTruncated),
        ("content_filter", AgentRunnerError.contentFiltered),
    ])
    func terminalFinishReasonsAreErrors(
        finishReason: String,
        expectedError: AgentRunnerError
    ) async throws {
        let runner = AgentRunner(
            client: ScriptedChatClient(responses: [
                AgentChatResponse(message: .assistant("Partial"), finishReason: finishReason),
            ]),
            toolExecutor: RecordingToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        await #expect(throws: expectedError) {
            try await runner.run(makeInput(currentUserMessage: .user("Run")))
        }
    }

    private func makeInput(currentUserMessage: AgentMessage) -> AgentRunInput {
        AgentRunInput(
            conversationID: UUID(),
            model: "test-model",
            apiKey: "test-key",
            systemMessages: [.system("System")],
            history: [],
            currentUserMessage: currentUserMessage,
            workspaceURL: FileManager.default.temporaryDirectory
        )
    }
}

private actor ScriptedChatClient: AgentChatCompleting {
    private var scriptedResponses: [AgentChatResponse]
    private var transientFailures: Int
    private var recordedRequests: [AgentChatRequest] = []

    init(responses: [AgentChatResponse], transientFailures: Int = 0) {
        self.scriptedResponses = responses
        self.transientFailures = transientFailures
    }

    func complete(_ request: AgentChatRequest, apiKey: String) async throws -> AgentChatResponse {
        recordedRequests.append(request)
        if transientFailures > 0 {
            transientFailures -= 1
            throw ScriptedClientError.transient
        }
        guard !scriptedResponses.isEmpty else { throw ScriptedClientError.noResponse }
        return scriptedResponses.removeFirst()
    }

    func requests() -> [AgentChatRequest] {
        recordedRequests
    }
}

private actor RecordingToolExecutor: AgentToolExecuting {
    private var recordedCalls: [AgentToolCall] = []
    private let resultContent: String
    private let artifacts: [AgentArtifact]

    init(
        resultContent: String = "/workspace",
        artifacts: [AgentArtifact] = []
    ) {
        self.resultContent = resultContent
        self.artifacts = artifacts
    }

    func availableTools() async -> [AgentToolDefinition] {
        [AgentToolDefinition(
            name: "terminal_execute",
            description: "Execute a command",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object(["type": .string("string")]),
                ]),
            ])
        )]
    }

    func execute(
        _ call: AgentToolCall,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        recordedCalls.append(call)
        return AgentToolExecutionResult(
            content: resultContent,
            metadata: ["exitCode": .number(0)],
            artifacts: artifacts
        )
    }

    func calls() -> [AgentToolCall] {
        recordedCalls
    }
}

private actor StoppableToolExecutor: AgentToolExecuting {
    private var continuation: CheckedContinuation<AgentToolExecutionResult, Never>?

    func availableTools() async -> [AgentToolDefinition] {
        [AgentToolDefinition(
            name: "terminal_execute",
            description: "Execute a command",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object(["type": .string("string")]),
                ]),
            ])
        )]
    }

    func execute(
        _ call: AgentToolCall,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancelCurrentTool(runID: UUID, callID: String) async -> Bool {
        guard continuation != nil else { return false }
        continuation?.resume(returning: AgentToolExecutionResult(
            content: "stopped by user",
            isError: true
        ))
        continuation = nil
        return true
    }

    func hasStarted() -> Bool {
        continuation != nil
    }
}

private actor BlockingChatClient: AgentChatCompleting {
    private var cancellations: [UUID] = []

    func complete(_ request: AgentChatRequest, apiKey: String) async throws -> AgentChatResponse {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return AgentChatResponse(message: .assistant("Too late"))
    }

    func cancel(runID: UUID) async {
        cancellations.append(runID)
    }

    func cancelledRunIDs() -> [UUID] {
        cancellations
    }
}

private actor FullSchemaToolExecutor: AgentToolExecuting {
    func availableTools() async -> [AgentToolDefinition] {
        OmniAgentToolDefinitions.all
    }

    func execute(
        _ call: AgentToolCall,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        Issue.record("No tool should execute when the fixed prompt exceeds context")
        return AgentToolExecutionResult(content: "unexpected", isError: true)
    }
}

nonisolated private enum ScriptedClientError: Error, AgentRetryClassifying {
    case transient
    case noResponse

    var isRetryable: Bool {
        self == .transient
    }
}

nonisolated private enum EventHandlerError: Error, Equatable {
    case saveFailed
}
