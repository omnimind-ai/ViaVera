import Foundation
import SwiftData
import Testing
@testable import Via_Vera

@Suite("Shared conversation memory")
@MainActor
struct SharedConversationMemoryTests {
    @Test("Successful chat facts accumulate in the same store used by task memory")
    func accumulatesSharedFacts() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: ConversationRecord.self, MessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ConversationRepository(modelContext: container.mainContext)
        let conversation = try repository.createConversation(providerID: nil, modelID: "model", mode: .chat)
        let user = AgentMessage.user("I prefer short answers in Chinese.")
        try repository.append(user, to: conversation)
        let reply = try repository.append(.assistant("Understood."), to: conversation)
        let store = MarkdownMemoryStore(paths: WorkspacePaths(
            root: directory.appending(path: "absent-workspace"),
            controlRoot: directory.appending(path: "control")
        ))
        let memory = SharedConversationMemory(store: store, conversations: repository)
        let client = MemoryQueueClient(response: """
        {"longTerm":[{"text":"I prefer short answers in Chinese.","evidence":"I prefer short answers in Chinese."}],"daily":[]}
        """)
        memory.enqueue(userMessage: user, responseMessageID: reply.id, conversationID: conversation.id,
                       model: ModelOption(id: "model"), apiKey: "test", client: client)
        #expect(memory.isUpdating)
        await memory.waitUntilIdle()
        #expect(!memory.isUpdating)
        #expect(memory.errorMessage == nil)
        #expect(try await store.loadLongTermMemory().contains("short answers in Chinese"))
        #expect(try await store.sharedPromptMemory(query: "answers").contains("short answers in Chinese"))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "absent-workspace").path))
        let requests = await client.requests()
        #expect(requests.count == 1)
        #expect(requests.allSatisfy { $0.tools.isEmpty })
        #expect(reply.memoryUsage.promptTokens == 100)
        #expect(reply.memoryUsage.completionTokens == 20)
        #expect(reply.promptTokens == 0)
    }

    @Test("Queued extraction never stores a message that was deleted")
    func deletedSourceIsDiscarded() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: ConversationRecord.self, MessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ConversationRepository(modelContext: container.mainContext)
        let conversation = try repository.createConversation(providerID: nil, modelID: "model", mode: .chat)
        let user = AgentMessage.user("I prefer short answers in Chinese.")
        try repository.append(user, to: conversation)
        let store = MarkdownMemoryStore(paths: WorkspacePaths(
            root: directory.appending(path: "workspace"), controlRoot: directory.appending(path: "control")
        ))
        let memory = SharedConversationMemory(store: store, conversations: repository)
        let client = MemoryQueueClient(response: "{}")
        memory.enqueue(userMessage: user, responseMessageID: UUID(), conversationID: conversation.id,
                       model: ModelOption(id: "model"), apiKey: "test", client: client)
        try repository.delete(conversation)
        await memory.waitUntilIdle()
        #expect(await client.requests().isEmpty)
        #expect(try await !store.loadLongTermMemory().contains("short answers"))
    }

    @Test("An extraction failure does not invalidate the finished chat")
    func extractionFailureIsSeparate() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: ConversationRecord.self, MessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = ConversationRepository(modelContext: container.mainContext)
        let conversation = try repository.createConversation(providerID: nil, modelID: "model", mode: .chat)
        let user = AgentMessage.user("I prefer short answers in Chinese.")
        try repository.append(user, to: conversation)
        let reply = try repository.append(.assistant("Understood."), to: conversation)
        try repository.updateRunOutcome(status: .completed, errorMessage: nil, usage: .zero, for: conversation)
        let store = MarkdownMemoryStore(paths: WorkspacePaths(
            root: directory.appending(path: "workspace"), controlRoot: directory.appending(path: "control")
        ))
        let memory = SharedConversationMemory(store: store, conversations: repository)
        memory.enqueue(userMessage: user, responseMessageID: reply.id, conversationID: conversation.id,
                       model: ModelOption(id: "model"), apiKey: "test", client: MemoryQueueClient(response: "invalid json"))
        await memory.waitUntilIdle()
        #expect(memory.errorMessage != nil)
        #expect(conversation.status == .completed)
        #expect(conversation.lastErrorMessage == nil)
        #expect(!memory.isUpdating)
        #expect(reply.memoryUsage.promptTokens == 100)
        let extractionError = memory.errorMessage
        _ = await memory.promptContext(query: "answers", maximumUTF8Bytes: 1_000)
        #expect(memory.errorMessage == extractionError)
    }
}

private actor MemoryQueueClient: AgentChatCompleting {
    private let response: String
    private var captured: [AgentChatRequest] = []
    init(response: String) { self.response = response }
    func complete(_ request: AgentChatRequest, apiKey: String) async throws -> AgentChatResponse {
        captured.append(request)
        return AgentChatResponse(
            message: .assistant(response),
            usage: AgentUsage(promptTokens: 100, completionTokens: 20, totalTokens: 120)
        )
    }
    func requests() -> [AgentChatRequest] { captured }
}
