import Foundation
import Testing
@testable import Via_Vera

@Suite("Response completion details")
@MainActor
struct ResponseCompletionPresentationTests {
    @Test("Tool execution, round gaps, and the final stream never expose completion details")
    func activeRoundsHideDetails() throws {
        let conversation = ConversationRecord(modelID: "test")
        try conversation.append(.user("Inspect"))
        let call = AgentToolCall(id: "inspect", name: "file_read", arguments: "{}")
        let assistant = try conversation.append(
            .assistant(toolCalls: [call]),
            usage: AgentUsage(promptTokens: 100, completionTokens: 10, totalTokens: 110)
        )
        let live = ChatToolLiveSnapshot(
            runID: UUID(), conversationID: conversation.id,
            assistantMessageIDs: [assistant.id], activeAssistantMessageID: assistant.id,
            activeCallID: call.id, terminalOutput: ""
        )
        let runningTool = ChatTranscriptPresentation(
            messages: conversation.orderedMessages, runIsActive: true, liveToolActivity: live
        )
        #expect(runningTool.activeAgentTurn != nil)
        #expect(runningTool.messages.allSatisfy { $0.completion == nil })
        #expect(runningTool.activeAgentTurn?.completion == nil)

        try conversation.append(.tool(callID: call.id, name: call.name, content: "Done"))
        let betweenRounds = ChatTranscriptPresentation(
            messages: conversation.orderedMessages, runIsActive: true, liveToolActivity: nil
        )
        #expect(betweenRounds.messages.allSatisfy { $0.completion == nil })

        let final = try conversation.append(.assistant("Working"), status: .streaming)
        let streaming = ChatTranscriptPresentation(
            messages: conversation.orderedMessages, runIsActive: true, liveToolActivity: nil
        )
        #expect(streaming.messages.allSatisfy { $0.completion == nil })
        // A completed individual model response still does not finish the run.
        try final.replacePayload(with: .assistant("Done", id: final.id), status: .completed)
        let finishing = ChatTranscriptPresentation(
            messages: conversation.orderedMessages, runIsActive: true, liveToolActivity: nil
        )
        #expect(finishing.messages.allSatisfy { $0.completion == nil })
    }

    @Test("Completed details aggregate all model rounds and preserve actual completion time")
    func finishedTurnDetails() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let conversation = ConversationRecord(modelID: "test")
        try conversation.append(.user("Inspect"), createdAt: start.addingTimeInterval(-2))
        let call = AgentToolCall(id: "inspect", name: "file_read", arguments: "{}")
        try conversation.append(
            .assistant(toolCalls: [call]),
            usage: AgentUsage(promptTokens: 100, completionTokens: 10, totalTokens: 140, cachedTokens: 30),
            createdAt: start
        )
        try conversation.append(.tool(callID: call.id, name: call.name, content: "Done"))
        let final = try conversation.append(.assistant("Done"), status: .streaming,
                                            createdAt: start.addingTimeInterval(40))
        try final.replacePayload(
            with: .assistant("Done", id: final.id), status: .completed,
            usage: AgentUsage(promptTokens: 200, completionTokens: 20, totalTokens: 270, cachedTokens: 50),
            updatedAt: start.addingTimeInterval(90)
        )
        final.memoryUsage = AgentUsage(promptTokens: 999, completionTokens: 999, totalTokens: 1_998)
        final.updatedAt = start.addingTimeInterval(400)
        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages, runIsActive: false, liveToolActivity: nil
        )
        let details = try #require(presentation.agentTurns.first?.completion)
        #expect(details.usage.contextTokens == 380)
        #expect(details.usage.outputTokens == 30)
        #expect(details.usage.cachedTokens == 80)
        #expect(details.elapsedSeconds == 90)
        #expect(details.completedAt == start.addingTimeInterval(90))
        #expect(presentation.messages.filter { $0.completion != nil }.count == 1)
    }

    @Test("A previous completed reply stays inspectable while the next turn runs")
    func previousTurnRemainsAvailable() throws {
        let conversation = ConversationRecord(modelID: "test")
        try conversation.append(.user("First"))
        let old = try conversation.append(.assistant("Finished"))
        try conversation.append(.user("Next"))
        let current = try conversation.append(.assistant("Working"), status: .streaming)
        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages, runIsActive: true, liveToolActivity: nil
        )
        #expect(presentation.messages.first { $0.id == old.id }?.completion != nil)
        #expect(presentation.messages.first { $0.id == current.id }?.completion == nil)
    }

    @Test("Legacy replies without usage or a completion timestamp retain timing details")
    func legacyReplyFallback() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let message = try MessageRecord(message: .assistant("Done"), sequence: 0,
                                       createdAt: start, updatedAt: start.addingTimeInterval(8))
        message.responseCompletedAt = nil
        let presentation = ChatTranscriptPresentation(
            messages: [message], runIsActive: false, liveToolActivity: nil
        )
        let details = try #require(presentation.messages.first?.completion)
        #expect(details.elapsedSeconds == 8)
        #expect(details.usage.cacheHitPercentage == nil)
        #expect(details.usage.outputTokens == 0)
    }
}
