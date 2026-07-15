import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent reasoning streaming")
struct AgentReasoningStreamingTests {
    @Test("Runner sequences cumulative reasoning before answer text under one assistant ID")
    func cumulativeReasoningSnapshotsUseFinalAssistantID() async throws {
        let providerMessageID = UUID()
        let providerSnapshots = [
            AgentStreamSnapshot(reasoningContent: "First step"),
            AgentStreamSnapshot(
                content: "Final answer",
                reasoningContent: "First step, then verify"
            ),
        ]
        let expectedSnapshots = [
            providerSnapshots[0],
            AgentStreamSnapshot(reasoningContent: "First step, then verify"),
            providerSnapshots[1],
        ]
        let client = ReasoningStreamingClient(
            snapshots: providerSnapshots,
            response: AgentChatResponse(message: AgentMessage.assistant(
                "Final answer",
                reasoningContent: "First step, then verify",
                id: providerMessageID
            ))
        )
        let recorder = ReasoningRunEventRecorder()
        let runID = UUID()
        let input = AgentRunInput(
            runID: runID,
            conversationID: UUID(),
            model: "reasoning-test-model",
            apiKey: "test-key",
            systemMessages: [.system("System")],
            history: [],
            currentUserMessage: .user("Think first"),
            workspaceURL: FileManager.default.temporaryDirectory,
            reasoningEffort: .medium,
            allowsToolCalls: false
        )
        let runner = AgentRunner(
            client: client,
            toolExecutor: ReasoningNoopToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        let result = try await runner.run(input) { event in
            await recorder.record(event)
        }

        let recorded = await recorder.snapshot()
        let assistantID = try #require(recorded.startedAssistantID)
        #expect(assistantID != providerMessageID)
        #expect(recorded.updateIDs == [assistantID, assistantID, assistantID])
        #expect(recorded.snapshots == expectedSnapshots)
        #expect(recorded.finalAssistantID == assistantID)
        #expect(result.finalMessage.id == assistantID)
        #expect(result.finalMessage.reasoningContent == "First step, then verify")
        #expect(await client.lastRequest()?.stream == true)
        #expect(await client.lastRequest()?.reasoningEffort == .medium)
    }

    @Test("Runner coalesces reasoning-only bursts and flushes the latest snapshot")
    func reasoningOnlyBurstsAreCoalesced() async throws {
        let snapshots = [
            AgentStreamSnapshot(reasoningContent: "one"),
            AgentStreamSnapshot(reasoningContent: "one two"),
            AgentStreamSnapshot(reasoningContent: "one two three"),
        ]
        let client = ReasoningStreamingClient(
            snapshots: snapshots,
            response: AgentChatResponse(message: .assistant(
                reasoningContent: "one two three"
            ))
        )
        let recorder = ReasoningRunEventRecorder()
        let runner = AgentRunner(
            client: client,
            toolExecutor: ReasoningNoopToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        _ = try await runner.run(makeInput()) { event in
            await recorder.record(event)
        }

        #expect(await recorder.snapshot().snapshots == [snapshots[0], snapshots[2]])
    }

    @Test("Coalescer flushes pending reasoning before answer text advances")
    func pendingReasoningPrecedesAnswerText() async throws {
        let snapshots = [
            AgentStreamSnapshot(reasoningContent: "one"),
            AgentStreamSnapshot(reasoningContent: "one two"),
            AgentStreamSnapshot(content: "answer", reasoningContent: "one two"),
        ]
        let recorder = CoalescedSnapshotRecorder()
        let coalescer = AgentStreamSnapshotCoalescer(
            minimumReasoningInterval: .seconds(60)
        ) { snapshot in
            await recorder.append(snapshot)
        }

        for snapshot in snapshots {
            try await coalescer.consume(snapshot)
        }

        #expect(await recorder.values() == snapshots)
    }

    @Test("Coalescer splits a first mixed snapshot at the reasoning boundary")
    func firstMixedSnapshotIsSequenced() async throws {
        let mixed = AgentStreamSnapshot(
            content: "answer",
            reasoningContent: "complete reasoning"
        )
        let recorder = CoalescedSnapshotRecorder()
        let coalescer = AgentStreamSnapshotCoalescer { snapshot in
            await recorder.append(snapshot)
        }

        try await coalescer.consume(mixed)

        #expect(await recorder.values() == [
            AgentStreamSnapshot(reasoningContent: "complete reasoning"),
            mixed,
        ])
    }

    @Test("Whitespace-only reasoning is not accepted as a completed response")
    func whitespaceOnlyReasoningIsRejected() async throws {
        let client = ReasoningStreamingClient(
            snapshots: [AgentStreamSnapshot(reasoningContent: "  \n")],
            response: AgentChatResponse(message: .assistant(reasoningContent: "  \n"))
        )
        let runner = AgentRunner(
            client: client,
            toolExecutor: ReasoningNoopToolExecutor(),
            retryPolicy: AgentRetryPolicy(maxAttempts: 1)
        )

        await #expect(throws: AgentRunnerError.emptyAssistantResponse) {
            try await runner.run(makeInput())
        }
    }

    private func makeInput() -> AgentRunInput {
        AgentRunInput(
            runID: UUID(),
            conversationID: UUID(),
            model: "reasoning-test-model",
            apiKey: "test-key",
            systemMessages: [.system("System")],
            history: [],
            currentUserMessage: .user("Think first"),
            workspaceURL: FileManager.default.temporaryDirectory,
            reasoningEffort: .medium,
            allowsToolCalls: false
        )
    }
}

private actor ReasoningStreamingClient: AgentChatStreaming {
    private let snapshots: [AgentStreamSnapshot]
    private let response: AgentChatResponse
    private var request: AgentChatRequest?

    init(snapshots: [AgentStreamSnapshot], response: AgentChatResponse) {
        self.snapshots = snapshots
        self.response = response
    }

    func complete(
        _ request: AgentChatRequest,
        apiKey: String
    ) async throws -> AgentChatResponse {
        self.request = request
        return response
    }

    func stream(
        _ request: AgentChatRequest,
        apiKey: String,
        onSnapshot: @escaping @Sendable (AgentStreamSnapshot) async throws -> Void
    ) async throws -> AgentChatResponse {
        self.request = request
        for snapshot in snapshots {
            try await onSnapshot(snapshot)
        }
        return response
    }

    func lastRequest() -> AgentChatRequest? {
        request
    }
}

private struct ReasoningNoopToolExecutor: AgentToolExecuting {
    private enum UnexpectedExecution: Error {
        case toolWasExecuted
    }

    func availableTools() async -> [AgentToolDefinition] {
        []
    }

    func execute(
        _ call: AgentToolCall,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        throw UnexpectedExecution.toolWasExecuted
    }
}

private actor ReasoningRunEventRecorder {
    struct Snapshot: Sendable {
        var startedAssistantID: UUID?
        var updateIDs: [UUID]
        var snapshots: [AgentStreamSnapshot]
        var finalAssistantID: UUID?
    }

    private var startedAssistantID: UUID?
    private var updateIDs: [UUID] = []
    private var snapshots: [AgentStreamSnapshot] = []
    private var finalAssistantID: UUID?

    func record(_ event: AgentRunEvent) {
        switch event {
        case let .assistantMessageStarted(id, _):
            startedAssistantID = id
        case let .assistantMessageUpdated(id, snapshot, _):
            updateIDs.append(id)
            snapshots.append(snapshot)
        case let .assistantMessage(message, _, _, _):
            finalAssistantID = message.id
        default:
            break
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            startedAssistantID: startedAssistantID,
            updateIDs: updateIDs,
            snapshots: snapshots,
            finalAssistantID: finalAssistantID
        )
    }
}

private actor CoalescedSnapshotRecorder {
    private var snapshots: [AgentStreamSnapshot] = []

    func append(_ snapshot: AgentStreamSnapshot) {
        snapshots.append(snapshot)
    }

    func values() -> [AgentStreamSnapshot] {
        snapshots
    }
}
