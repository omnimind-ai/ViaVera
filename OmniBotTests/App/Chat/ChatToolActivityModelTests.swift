import Foundation
import Testing
@testable import Via_Vera

@Suite("Chat tool live activity")
struct ChatToolActivityModelTests {
    @Test("Terminal output is scoped to its run and cleared on completion")
    @MainActor
    func scopesTerminalOutputToRun() throws {
        let model = ChatToolActivityModel()
        let runID = UUID()
        let conversationID = UUID()
        let assistantMessageID = UUID()
        let call = AgentToolCall(
            id: "terminal",
            name: "terminal_execute",
            arguments: #"{"tool_title":"运行命令","command":"pwd"}"#
        )

        model.beginRun(runID: runID, conversationID: conversationID)
        model.registerAssistantMessage(id: assistantMessageID, runID: runID)
        model.beginTool(call, runID: runID)
        model.appendTerminalOutput(
            "ignored run",
            isStandardError: false,
            runID: UUID(),
            callID: call.id
        )
        model.appendTerminalOutput(
            "ignored call",
            isStandardError: false,
            runID: runID,
            callID: "another_call"
        )
        model.appendTerminalOutput(
            "/workspace",
            isStandardError: false,
            runID: runID,
            callID: call.id
        )
        model.flushPendingTerminalOutput()

        let active = try #require(model.snapshot(for: conversationID))
        #expect(active.assistantMessageIDs == [assistantMessageID])
        #expect(active.activeAssistantMessageID == assistantMessageID)
        #expect(active.activeCallID == call.id)
        #expect(active.terminalOutput == "/workspace\n")

        model.completeTool(callID: call.id, runID: runID)
        #expect(model.snapshot(for: conversationID)?.activeCallID == nil)
        #expect(model.snapshot(for: conversationID)?.activeAssistantMessageID == nil)
        #expect(model.snapshot(for: conversationID)?.assistantMessageIDs == [assistantMessageID])
        #expect(model.snapshot(for: conversationID)?.terminalOutput.isEmpty == true)

        model.endRun(runID: runID)
        #expect(model.snapshot(for: conversationID) == nil)
    }

    @Test("A tool is activated under the most recently registered assistant")
    @MainActor
    func tracksActiveAssistantOccurrence() throws {
        let model = ChatToolActivityModel()
        let runID = UUID()
        let conversationID = UUID()
        let firstAssistantID = UUID()
        let secondAssistantID = UUID()
        let call = AgentToolCall(
            id: "reused_call_id",
            name: "terminal_execute",
            arguments: #"{"tool_title":"运行命令","command":"pwd"}"#
        )

        model.beginRun(runID: runID, conversationID: conversationID)
        model.registerAssistantMessage(id: firstAssistantID, runID: runID)
        model.registerAssistantMessage(id: secondAssistantID, runID: runID)
        model.beginTool(call, runID: runID)

        let snapshot = try #require(model.snapshot(for: conversationID))
        #expect(snapshot.assistantMessageIDs == [firstAssistantID, secondAssistantID])
        #expect(snapshot.activeAssistantMessageID == secondAssistantID)
        #expect(snapshot.activeCallID == call.id)
    }
}
