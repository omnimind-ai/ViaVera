import Foundation
import SwiftData
import Testing
@testable import Via_Vera

@Suite("Model usage persistence")
struct ModelUsageReaderTests {
    @Test("Streaming completion keeps the original model after the conversation selection changes")
    @MainActor
    func modelSnapshot() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repository = ConversationRepository(modelContext: context)
        let conversation = try repository.createConversation(providerID: "provider-a", modelID: "model-a")
        let assistantID = UUID()
        try repository.updateStreamingAssistant(
            id: assistantID, snapshot: AgentStreamSnapshot(), in: conversation
        )
        try repository.updateModel(providerID: "provider-b", modelID: "model-b", for: conversation)
        let message = try repository.append(
            .assistant("First response", id: assistantID), to: conversation,
            usage: AgentUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15)
        )
        try repository.append(
            .assistant("Second response"), to: conversation,
            usage: AgentUsage(promptTokens: 20, completionTokens: 5, totalTokens: 25)
        )
        let legacy = try repository.append(.assistant("Legacy response"), to: conversation)
        legacy.modelID = nil
        try context.save()

        #expect(message.modelID == "model-a")
        #expect(message.providerID == "provider-a")
        #expect(conversation.messages.count == 3)
        let summary = try await ModelUsageReader.read(
            container: container, range: .week, now: .now, calendar: .current
        )
        #expect(summary.total.responseCount == 3)
        #expect(summary.total.totalTokens == 40)
        #expect(summary.models.first { $0.modelID == "model-a" }?.totalTokens == 15)
        #expect(summary.models.first { $0.modelID == "model-b" }?.totalTokens == 25)
        #expect(summary.hasUnknownModels)
    }

    @Test("Paged scalar fetches retain every message and reflect deleted conversations")
    @MainActor
    func pagingAndDeletion() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conversation = ConversationRecord(modelID: "model")
        context.insert(conversation)
        let now = Date.now
        for index in 0..<503 {
            let record = try MessageRecord(
                message: .user("Message \(index)"), sequence: index,
                createdAt: now, conversation: conversation
            )
            context.insert(record)
        }
        try context.save()
        let summary = try await ModelUsageReader.read(
            container: container, range: .week, now: now, calendar: .current
        )
        #expect(summary.total.messageCount == 503)

        context.delete(conversation)
        try context.save()
        let afterDeletion = try await ModelUsageReader.read(
            container: container, range: .week, now: now, calendar: .current
        )
        #expect(afterDeletion.total.messageCount == 0)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ConversationRecord.self, MessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
