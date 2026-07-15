import Foundation
import SwiftData
import Testing
@testable import Via_Vera

@Suite("Reasoning persistence")
struct ReasoningPersistenceTests {
    @Test("Reasoning-only streaming assistants survive finalization")
    @MainActor
    func reasoningOnlyStreamingFinalization() throws {
        let (container, repository, conversation) = try makeRepository()
        _ = container
        let assistantID = UUID()

        try repository.updateStreamingAssistant(
            id: assistantID,
            snapshot: AgentStreamSnapshot(reasoningContent: "Still working through it"),
            in: conversation
        )
        repository.finalizeStreamingAssistants(in: conversation, status: .interrupted)

        let record = try #require(
            conversation.orderedMessages.first(where: { $0.id == assistantID })
        )
        #expect(record.status == .interrupted)
        #expect(record.content == nil)
        #expect(try record.decodeMessage().reasoningContent == "Still working through it")
    }

    @Test("Interrupted-run recovery preserves a reasoning-only assistant")
    @MainActor
    func interruptedRunRecovery() throws {
        let (container, repository, conversation) = try makeRepository(status: .running)
        let assistantID = UUID()
        try repository.updateStreamingAssistant(
            id: assistantID,
            snapshot: AgentStreamSnapshot(reasoningContent: "Recovered reasoning"),
            in: conversation
        )

        #expect(try repository.recoverInterruptedRuns() == 1)

        let recovered = try #require(repository.conversation(id: conversation.id))
        let record = try #require(
            recovered.orderedMessages.first(where: { $0.id == assistantID })
        )
        #expect(recovered.status == .failed)
        #expect(record.status == .interrupted)
        #expect(try record.decodeMessage().reasoningContent == "Recovered reasoning")

        let reloadedRepository = ConversationRepository(
            modelContext: ModelContext(container)
        )
        try reloadedRepository.reload()
        let reloaded = try #require(reloadedRepository.conversation(id: conversation.id))
        let reloadedMessage = try #require(
            reloaded.orderedMessages.first(where: { $0.id == assistantID })
        )
        #expect(try reloadedMessage.decodeMessage().reasoningContent == "Recovered reasoning")
    }

    @Test("Repository bounds streamed reasoning before storing its payload")
    @MainActor
    func streamedReasoningIsBounded() throws {
        let (container, repository, conversation) = try makeRepository()
        _ = container
        let assistantID = UUID()
        let original = String(
            repeating: "x",
            count: AgentReasoningContent.maximumPersistedCharacters + 100
        )

        try repository.updateStreamingAssistant(
            id: assistantID,
            snapshot: AgentStreamSnapshot(reasoningContent: original),
            in: conversation
        )

        let record = try #require(
            conversation.orderedMessages.first(where: { $0.id == assistantID })
        )
        let reasoning = try record.decodeMessage().reasoningContent
        #expect(reasoning?.count == AgentReasoningContent.maximumPersistedCharacters)
        #expect(reasoning?.hasPrefix(AgentReasoningContent.truncationNotice) == true)
    }

    @Test("Whitespace-only interrupted reasoning placeholders are removed")
    @MainActor
    func whitespaceReasoningPlaceholderIsRemoved() throws {
        let (container, repository, conversation) = try makeRepository()
        _ = container
        let assistantID = UUID()
        try repository.updateStreamingAssistant(
            id: assistantID,
            snapshot: AgentStreamSnapshot(reasoningContent: "  \n"),
            in: conversation
        )

        repository.finalizeStreamingAssistants(in: conversation, status: .interrupted)

        #expect(!conversation.orderedMessages.contains(where: { $0.id == assistantID }))
    }

    @MainActor
    private func makeRepository(
        status: ConversationStatus = .idle
    ) throws -> (ModelContainer, ConversationRepository, ConversationRecord) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(
            modelID: "reasoning-test-model",
            status: status
        )
        context.insert(conversation)
        try context.save()

        let repository = ConversationRepository(modelContext: context)
        try repository.reload()
        return (container, repository, conversation)
    }
}
