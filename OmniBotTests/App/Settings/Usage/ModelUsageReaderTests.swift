import Foundation
import SwiftData
import Testing
@testable import Via_Vera

@Suite("Model usage persistence")
struct ModelUsageReaderTests {
    @Test("Background memory usage persists and counts tokens without changing context or response counts")
    @MainActor
    func memoryUsageAccounting() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repository = ConversationRepository(modelContext: context)
        let conversation = try repository.createConversation(providerID: "provider", modelID: "original", mode: .chat)
        try repository.append(.user("I prefer short answers."), to: conversation)
        let response = try repository.append(
            .assistant("Understood."), to: conversation,
            usage: AgentUsage(promptTokens: 100, completionTokens: 20, totalTokens: 150,
                              cachedTokens: 30, cacheCreationTokens: 10),
            contextWindow: 8_192
        )
        #expect(response.memoryUsageData == nil)
        #expect(response.memoryUsage == .zero)
        let first = AgentUsage(promptTokens: 50, completionTokens: 10, totalTokens: 75,
                               cachedTokens: 15, cacheCreationTokens: 10)
        let second = AgentUsage(promptTokens: 20, completionTokens: 5, totalTokens: 25,
                                cacheCreationTokens: 5)
        #expect(try repository.appendMemoryUsage(first, toMessageID: response.id, in: conversation.id))
        #expect(try repository.appendMemoryUsage(second, toMessageID: response.id, in: conversation.id))
        try repository.updateModel(providerID: "other-provider", modelID: "other", for: conversation)

        let reloadedRepository = ConversationRepository(modelContext: ModelContext(container))
        try reloadedRepository.reload()
        let restoredConversation = try #require(reloadedRepository.conversation(id: conversation.id))
        let restored = try #require(restoredConversation.messages.first { $0.id == response.id })
        #expect(restored.memoryUsage == first + second)
        #expect(restored.promptTokens == 100)
        #expect(restored.completionTokens == 20)
        #expect(restored.cachedTokens == 30)
        #expect(restored.cacheCreationTokens == 10)
        #expect(restored.contextWindow == 8_192)
        #expect(restored.modelID == "original")
        let summary = try await ModelUsageReader.read(container: container, range: .week, now: .now, calendar: .current)
        #expect(summary.total.messageCount == 1)
        #expect(summary.total.responseCount == 1)
        #expect(summary.total.inputTokens == 170)
        #expect(summary.total.outputTokens == 35)
        #expect(summary.total.cachedTokens == 45)
        #expect(summary.total.cacheCreationTokens == 25)
        #expect(summary.total.totalTokens == 250)
        #expect(summary.models.first { $0.modelID == "original" }?.totalTokens == 250)
        #expect(!summary.models.contains { $0.modelID == "other" })

        try repository.delete(conversation)
        #expect(try !repository.appendMemoryUsage(first, toMessageID: response.id, in: conversation.id))
        #expect(repository.conversations.isEmpty)
    }

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
