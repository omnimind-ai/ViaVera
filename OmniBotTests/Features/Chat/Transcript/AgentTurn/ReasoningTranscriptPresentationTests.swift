import Testing
@testable import Via_Vera

@Suite("Reasoning transcript presentation")
struct ReasoningTranscriptPresentationTests {
    @Test("A completed reasoning-only assistant is folded into its Agent turn")
    @MainActor
    func reasoningOnlyAssistantFoldsIntoAgentTurn() throws {
        let conversation = ConversationRecord(modelID: "reasoning-test-model")
        let firstUser = try conversation.append(.user("First question"))
        let assistant = try conversation.append(.assistant(
            reasoningContent: "A reasoning-only provider response"
        ))
        let secondUser = try conversation.append(.user("Follow-up"))

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )

        #expect(presentation.messages.map(\.id) == [firstUser.id, assistant.id, secondUser.id])
        #expect(
            presentation.messages.first(where: { $0.id == assistant.id })?.reasoningContent
                == "A reasoning-only provider response"
        )
        #expect(presentation.timelineEntries.compactMap(\.message?.id) == [
            firstUser.id,
            secondUser.id,
        ])
        let turn = try #require(presentation.agentTurns.first)
        #expect(turn.id == firstUser.id)
        #expect(turn.processMessages.map(\.id) == [assistant.id])
        #expect(turn.processMessages.first?.content == nil)
        #expect(turn.processMessages.first?.reasoningContent
            == "A reasoning-only provider response")
        #expect(turn.processMessages.first?.isReasoningStreaming == false)
        #expect(turn.visibleMessages.isEmpty)
    }

    @Test("Reasoning stays attached to its assistant across a tool turn")
    @MainActor
    func reasoningOrderAcrossToolTurn() throws {
        let conversation = ConversationRecord(modelID: "reasoning-test-model")
        let user = try conversation.append(.user("Inspect"))
        let call = AgentToolCall(
            id: "reasoning_tool",
            name: "file_read",
            arguments: #"{"path":"README.md"}"#
        )
        let process = try conversation.append(.assistant(
            reasoningContent: "I should inspect the file first.",
            toolCalls: [call]
        ))
        try conversation.append(.tool(
            callID: call.id,
            name: call.name,
            content: #"{"success":true,"content":"Read"}"#
        ))
        let final = try conversation.append(.assistant(
            "Done",
            reasoningContent: "The file confirms the answer."
        ))

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: false,
            liveToolActivity: nil
        )

        let turn = try #require(presentation.agentTurns.first)
        #expect(turn.id == user.id)
        #expect(turn.processMessages.map(\.id) == [process.id, final.id])
        #expect(turn.visibleMessages.map(\.id) == [final.id])
        #expect(turn.processMessages.first?.reasoningContent == "I should inspect the file first.")
        #expect(turn.processMessages.last?.content == nil)
        #expect(turn.processMessages.last?.reasoningContent == "The file confirms the answer.")
        #expect(turn.processMessages.last?.isReasoningStreaming == false)
        #expect(turn.visibleMessages.first?.content == "Done")
        #expect(turn.visibleMessages.first?.reasoningContent == nil)
    }

    @Test("A reasoning-only stream remains in the thinking phase")
    @MainActor
    func reasoningOnlyStreamKeepsThinkingPhase() throws {
        let conversation = ConversationRecord(modelID: "reasoning-test-model")
        try conversation.append(.user("Think first"))
        let assistant = try conversation.append(
            .assistant(reasoningContent: "Still reasoning"),
            status: .streaming
        )

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: true,
            liveToolActivity: nil
        )

        let turn = try #require(presentation.agentTurns.first)
        let process = try #require(turn.processMessages.first)
        #expect(process.id == assistant.id)
        #expect(process.isReasoningStreaming)
        #expect(turn.visibleMessages.isEmpty)
    }

    @Test("The first answer text ends the reasoning streaming phase")
    @MainActor
    func answerTextEndsReasoningStreamingPhase() throws {
        let conversation = ConversationRecord(modelID: "reasoning-test-model")
        try conversation.append(.user("Think first"))
        let assistant = try conversation.append(
            .assistant("Answer", reasoningContent: "Finished reasoning"),
            status: .streaming
        )

        let presentation = ChatTranscriptPresentation(
            messages: conversation.orderedMessages,
            runIsActive: true,
            liveToolActivity: nil
        )

        let turn = try #require(presentation.agentTurns.first)
        let process = try #require(turn.processMessages.first)
        let visible = try #require(turn.visibleMessages.first)
        #expect(process.id == assistant.id)
        #expect(process.reasoningContent == "Finished reasoning")
        #expect(process.isReasoningStreaming == false)
        #expect(visible.content == "Answer")
        #expect(visible.isReasoningStreaming == false)
    }
}
