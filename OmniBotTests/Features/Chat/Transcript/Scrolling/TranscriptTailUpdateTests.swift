import Foundation
import Testing
@testable import Via_Vera

@Suite("Transcript visible tail updates")
@MainActor
struct TranscriptTailUpdateTests {
    @Test("Background usage and synchronization updates do not request scrolling")
    func bookkeepingDoesNotMoveTranscript() throws {
        let record = try MessageRecord(message: .assistant("A completed reply"), sequence: 0)
        let before = TranscriptTailUpdate(record)
        record.updatedAt = record.updatedAt.addingTimeInterval(30)
        record.promptTokens += 100
        record.memoryUsage = AgentUsage(promptTokens: 80, completionTokens: 20, totalTokens: 100)
        #expect(TranscriptTailUpdate(record) == before)
    }

    @Test("New text, reasoning, status, and messages still request following")
    func visibleUpdatesAreDetected() throws {
        let record = try MessageRecord(message: .assistant("Initial"), sequence: 0, status: .streaming)
        let initial = TranscriptTailUpdate(record)
        var message = try record.decodeMessage()
        message.content = "Initial text extended"
        try record.replacePayload(with: message)
        let textUpdate = TranscriptTailUpdate(record)
        #expect(textUpdate != initial)

        message.reasoningContent = "Reasoning extended"
        try record.replacePayload(with: message)
        let reasoningUpdate = TranscriptTailUpdate(record)
        #expect(reasoningUpdate != textUpdate)
        record.status = .completed
        #expect(TranscriptTailUpdate(record) != reasoningUpdate)

        let next = try MessageRecord(message: .assistant("Initial text extended"), sequence: 1)
        #expect(TranscriptTailUpdate(next) != TranscriptTailUpdate(record))
    }
}
