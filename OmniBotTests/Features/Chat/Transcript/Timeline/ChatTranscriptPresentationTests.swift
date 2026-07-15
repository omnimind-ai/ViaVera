import Foundation
import Testing
@testable import Via_Vera

@Suite("Chat transcript presentation")
struct ChatTranscriptPresentationTests {
    @Test("Tool calls absorb role=tool results and use tool_title")
    @MainActor
    func mergesToolResultsIntoCallingAssistant() throws {
        let conversation = ConversationRecord(modelID: "test-model")
        try conversation.append(.user("Inspect the workspace"))
        let call = AgentToolCall(
            id: "call_terminal",
            name: "terminal_execute",
            arguments: #"{"tool_title":"检查工作区","command":"pwd"}"#
        )
        let callingAssistant = try conversation.append(
            .assistant(toolCalls: [call]),
            usage: AgentUsage(
                promptTokens: 100,
                completionTokens: 12,
                totalTokens: 112,
                cachedTokens: 20
            ),
            contextWindow: 1_000_000
        )
        try conversation.append(
            .tool(
                callID: call.id,
                name: call.name,
                content: #"{"content":"/workspace","metadata":{"exitCode":0,"toolTitle":"fallback"},"success":true}"#
            )
        )
        let finalAssistant = try conversation.append(
            .assistant("Done"),
            usage: AgentUsage(
                promptTokens: 240,
                completionTokens: 30,
                totalTokens: 270,
                cachedTokens: 50
            ),
            contextWindow: 1_000_000
        )

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )

        #expect(presentation.messages.count == 3)
        #expect(presentation.messages.allSatisfy { $0.message.role != .tool })
        let tool = try #require(
            presentation.messages.first(where: { $0.id == callingAssistant.id })?
                .toolCalls.first
        )
        #expect(tool.title == "检查工作区")
        #expect(tool.output == "/workspace")
        #expect(tool.status == .succeeded)
        #expect(presentation.latestTurnTools == [tool])
        #expect(
            presentation.messages.first(where: { $0.id == callingAssistant.id })?
                .turnUsage == nil
        )

        let usage = try #require(
            presentation.messages.first(where: { $0.id == finalAssistant.id })?
                .turnUsage
        )
        #expect(usage.contextTokens == 290)
        #expect(usage.inputTokens == 240)
        #expect(usage.outputTokens == 30)
        #expect(usage.cachedTokens == 50)
    }

    @Test("Browser tool calls expose browser thumbnail metadata")
    @MainActor
    func browserToolPresentationMetadata() throws {
        let conversation = ConversationRecord(modelID: "test-model")
        try conversation.append(.user("Open the documentation"))
        let call = AgentToolCall(
            id: "call_browser",
            name: "browser_use",
            arguments: #"{"tool_title":"打开文档","action":"navigate","url":"https://example.com"}"#
        )
        let assistant = try conversation.append(.assistant(toolCalls: [call]))
        try conversation.append(.tool(
            callID: call.id,
            name: call.name,
            content: #"{"content":"Navigated.","metadata":{"title":"Example","url":"https://example.com/docs"},"success":true}"#
        ))

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )
        let tool = try #require(
            presentation.messages.first(where: { $0.id == assistant.id })?
                .toolCalls.first
        )

        #expect(tool.isBrowser)
        #expect(!tool.isTerminal)
        #expect(tool.symbolName == "safari")
        #expect(tool.typeLabel == "浏览器")
        #expect(tool.browserTitle == "Example")
        #expect(tool.browserURL == "https://example.com/docs")
    }

    @Test("An interrupted tool-only turn shows usage once on its last assistant")
    @MainActor
    func interruptedTurnUsesLastAssistant() throws {
        let conversation = ConversationRecord(modelID: "test-model")
        let user = try conversation.append(.user("Run it"))
        let call = AgentToolCall(
            id: "call_pending",
            name: "file_read",
            arguments: #"{"tool_title":"读取文件","path":"README.md"}"#
        )
        let assistant = try conversation.append(
            .assistant(toolCalls: [call]),
            usage: AgentUsage(
                promptTokens: .max,
                completionTokens: 1,
                totalTokens: .max,
                cachedTokens: 1
            )
        )

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )

        #expect(presentation.latestUserMessageID == user.id)
        let stoppedTool = try #require(
            presentation.messages.first(where: { $0.id == assistant.id })?.toolCalls.first
        )
        #expect(stoppedTool.status == .interrupted)
        #expect(!stoppedTool.wasStarted)
        #expect(presentation.messages.first(where: { $0.id == assistant.id })?
            .turnUsage?.contextTokens == .max)
    }

    @Test("A user-stopped tool result is presented as interrupted")
    @MainActor
    func stoppedToolResultIsInterrupted() throws {
        let conversation = ConversationRecord(modelID: "test-model")
        try conversation.append(.user("Stop the command"))
        let call = AgentToolCall(
            id: "call_stopped",
            name: "terminal_execute",
            arguments: #"{"tool_title":"Long command","command":"sleep 30"}"#
        )
        let assistant = try conversation.append(.assistant(toolCalls: [call]))
        try conversation.append(
            .tool(
                callID: call.id,
                name: call.name,
                content: #"{"content":"用户已停止当前工具调用。","metadata":{"interrupted":true},"success":false}"#
            ),
            status: .failed
        )

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )

        let stoppedTool = try #require(
            presentation.messages.first(where: { $0.id == assistant.id })?
                .toolCalls.first
        )
        #expect(stoppedTool.status == .interrupted)
        #expect(stoppedTool.wasStarted)
    }

    @Test("Live terminal output is attached only to the active call")
    @MainActor
    func liveTerminalOutputOverridesPendingResult() throws {
        let conversationID = UUID()
        let conversation = ConversationRecord(id: conversationID, modelID: "test-model")
        try conversation.append(.user("Run tools"))
        let first = AgentToolCall(
            id: "first",
            name: "terminal_execute",
            arguments: #"{"tool_title":"第一个命令","command":"echo one"}"#
        )
        let second = AgentToolCall(
            id: "second",
            name: "terminal_execute",
            arguments: #"{"tool_title":"第二个命令","command":"echo two"}"#
        )
        let callingAssistant = try conversation.append(.assistant(toolCalls: [first, second]))
        let runID = UUID()

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: true,
            liveToolActivity: ChatToolLiveSnapshot(
                runID: runID,
                conversationID: conversationID,
                assistantMessageIDs: [callingAssistant.id],
                activeAssistantMessageID: callingAssistant.id,
                activeCallID: first.id,
                terminalOutput: "one\n"
            )
        )

        #expect(presentation.latestTurnTools.map(\.status) == [.running, .pending])
        #expect(presentation.latestTurnTools.first?.output == "one")
        #expect(presentation.latestTurnTools.last?.output.isEmpty == true)
    }

    @Test("Repeated call IDs across rounds bind to their nearest assistant transaction")
    @MainActor
    func repeatedCallIDsUseNearestResult() throws {
        let conversation = ConversationRecord(modelID: "test-model")
        try conversation.append(.user("Run two rounds"))
        let firstCall = AgentToolCall(
            id: "reused_call_id",
            name: "terminal_execute",
            arguments: #"{"tool_title":"First command","command":"echo first"}"#
        )
        let firstAssistant = try conversation.append(.assistant(toolCalls: [firstCall]))
        try conversation.append(.tool(
            callID: firstCall.id,
            name: firstCall.name,
            content: #"{"content":"first result","metadata":{},"success":true}"#
        ))
        let secondCall = AgentToolCall(
            id: "reused_call_id",
            name: "terminal_execute",
            arguments: #"{"tool_title":"Second command","command":"echo second"}"#
        )
        let secondAssistant = try conversation.append(.assistant(toolCalls: [secondCall]))
        try conversation.append(.tool(
            callID: secondCall.id,
            name: secondCall.name,
            content: #"{"content":"second result","metadata":{},"success":true}"#
        ))
        try conversation.append(.assistant("Done"))

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )
        let firstTool = try #require(
            presentation.messages.first(where: { $0.id == firstAssistant.id })?.toolCalls.first
        )
        let secondTool = try #require(
            presentation.messages.first(where: { $0.id == secondAssistant.id })?.toolCalls.first
        )

        #expect(firstTool.callID == secondTool.callID)
        #expect(firstTool.id != secondTool.id)
        #expect(firstTool.output == "first result")
        #expect(secondTool.output == "second result")
        #expect(presentation.latestTurnTools == [firstTool, secondTool])
    }

    @Test("Live state is scoped to the current run assistant occurrence")
    @MainActor
    func liveStateDoesNotReviveHistoricalMissingResult() throws {
        let conversationID = UUID()
        let conversation = ConversationRecord(id: conversationID, modelID: "test-model")
        try conversation.append(.user("Old turn"))
        let oldCall = AgentToolCall(
            id: "reused_call_id",
            name: "terminal_execute",
            arguments: #"{"tool_title":"Old command","command":"echo old"}"#
        )
        let oldAssistant = try conversation.append(.assistant(toolCalls: [oldCall]))

        try conversation.append(.user("Current turn"))
        let currentCall = AgentToolCall(
            id: "reused_call_id",
            name: "terminal_execute",
            arguments: #"{"tool_title":"Current command","command":"echo current"}"#
        )
        let currentAssistant = try conversation.append(.assistant(toolCalls: [currentCall]))
        let runID = UUID()

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: true,
            liveToolActivity: ChatToolLiveSnapshot(
                runID: runID,
                conversationID: conversationID,
                assistantMessageIDs: [currentAssistant.id],
                activeAssistantMessageID: currentAssistant.id,
                activeCallID: currentCall.id,
                terminalOutput: "current output\n"
            )
        )
        let oldTool = try #require(
            presentation.messages.first(where: { $0.id == oldAssistant.id })?.toolCalls.first
        )
        let currentTool = try #require(
            presentation.messages.first(where: { $0.id == currentAssistant.id })?.toolCalls.first
        )

        #expect(oldTool.status == .interrupted)
        #expect(oldTool.output.isEmpty)
        #expect(currentTool.status == .running)
        #expect(currentTool.output == "current output")
        #expect(oldTool.id != currentTool.id)
    }

    @Test("Completed tool rounds collapse into one turn while final text stays visible")
    @MainActor
    func completedToolRoundBuildsCollapsedTurn() throws {
        let conversation = ConversationRecord(modelID: "test-model")
        let user = try conversation.append(.user("Inspect"))
        let call = AgentToolCall(
            id: "call_inspect",
            name: "terminal_execute",
            arguments: #"{"tool_title":"Inspect workspace","command":"pwd"}"#
        )
        let process = try conversation.append(.assistant(toolCalls: [call]))
        try conversation.append(.tool(
            callID: call.id,
            name: call.name,
            content: #"{"content":"/workspace","metadata":{},"success":true}"#
        ))
        let activePresentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: true,
            liveToolActivity: ChatToolLiveSnapshot(
                runID: UUID(),
                conversationID: conversation.id,
                assistantMessageIDs: [process.id],
                activeAssistantMessageID: nil,
                activeCallID: nil,
                terminalOutput: ""
            )
        )
        #expect(activePresentation.activeAgentTurn?.id == user.id)

        let final = try conversation.append(.assistant("Workspace inspected"))

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )

        #expect(presentation.timelineEntries.count == 2)
        let turn = try #require(presentation.timelineEntries.last?.agentTurn)
        #expect(turn.id == user.id)
        #expect(turn.isActive == false)
        #expect(activePresentation.activeAgentTurn?.id == turn.id)
        #expect(turn.processMessages.map(\.id) == [process.id])
        #expect(turn.visibleMessages.map(\.id) == [final.id])
        #expect(turn.tools.map(\.callID) == [call.id])
        #expect(turn.activityTools.map(\.callID) == [call.id])
        #expect(presentation.toolActivityTurn(preferredCompletedTurnID: nil) == nil)
        #expect(
            presentation.toolActivityTurn(preferredCompletedTurnID: user.id)?.id == user.id
        )
    }

    @Test("Active turn is derived as expanded and exposes only started tools")
    @MainActor
    func activeTurnFiltersPendingActivityTools() throws {
        let conversationID = UUID()
        let conversation = ConversationRecord(id: conversationID, modelID: "test-model")
        let user = try conversation.append(.user("Run two tools"))
        let running = AgentToolCall(
            id: "running",
            name: "terminal_execute",
            arguments: #"{"tool_title":"Running","command":"sleep 1"}"#
        )
        let pending = AgentToolCall(
            id: "pending",
            name: "file_read",
            arguments: #"{"tool_title":"Pending","path":"README.md"}"#
        )
        let assistant = try conversation.append(.assistant(toolCalls: [running, pending]))
        let runID = UUID()

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: true,
            liveToolActivity: ChatToolLiveSnapshot(
                runID: runID,
                conversationID: conversationID,
                assistantMessageIDs: [assistant.id],
                activeAssistantMessageID: assistant.id,
                activeCallID: running.id,
                terminalOutput: "working\n"
            )
        )

        let turn = try #require(presentation.activeAgentTurn)
        #expect(turn.id == user.id)
        #expect(turn.isActive)
        let rawTools = try #require(
            presentation.messages.first(where: { $0.id == assistant.id })?.toolCalls
        )
        #expect(rawTools.map(\.status) == [.running, .pending])
        #expect(turn.tools.map(\.status) == [.running])
        #expect(turn.activityTools.map(\.status) == [.running])
        #expect(
            presentation.toolActivityTurn(preferredCompletedTurnID: UUID())?.id == user.id
        )

        let beforeToolStart = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: true,
            liveToolActivity: ChatToolLiveSnapshot(
                runID: runID,
                conversationID: conversationID,
                assistantMessageIDs: [assistant.id],
                activeAssistantMessageID: nil,
                activeCallID: nil,
                terminalOutput: ""
            )
        )
        #expect(beforeToolStart.activeAgentTurn == nil)
        #expect(beforeToolStart.toolActivityTurn(preferredCompletedTurnID: UUID()) == nil)
    }

    @Test("Unstarted calls never enter a completed turn or pinned tool history")
    @MainActor
    func completedTurnExcludesUnstartedCalls() throws {
        let conversation = ConversationRecord(modelID: "test-model")
        try conversation.append(.user("Run in order"))
        let started = AgentToolCall(
            id: "started",
            name: "terminal_execute",
            arguments: #"{"tool_title":"Started","command":"pwd"}"#
        )
        let neverStarted = AgentToolCall(
            id: "never-started",
            name: "file_read",
            arguments: #"{"tool_title":"Never started","path":"README.md"}"#
        )
        let assistant = try conversation.append(
            .assistant(toolCalls: [started, neverStarted])
        )
        try conversation.append(.tool(
            callID: started.id,
            name: started.name,
            content: #"{"content":"/workspace","metadata":{},"success":true}"#
        ))
        try conversation.append(.assistant("Stopped before the second call"))

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )

        let rawTools = try #require(
            presentation.messages.first(where: { $0.id == assistant.id })?.toolCalls
        )
        #expect(rawTools.map(\.wasStarted) == [true, false])
        #expect(rawTools.map(\.status) == [.succeeded, .interrupted])
        let turn = try #require(presentation.agentTurns.first)
        #expect(turn.tools.map(\.callID) == [started.id])
        #expect(turn.activityTools.map(\.callID) == [started.id])
    }
}
