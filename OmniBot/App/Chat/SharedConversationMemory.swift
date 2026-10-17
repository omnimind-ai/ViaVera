import Foundation
import Observation

/// Host-managed memory work stays outside the chat tool loop and never blocks
/// sending the next message. Jobs are serialized to preserve write order.
@MainActor
@Observable
final class SharedConversationMemory {
    private(set) var pendingCount = 0
    private var readErrorMessage: String?
    private var consolidationErrorMessage: String?
    var errorMessage: String? { consolidationErrorMessage ?? readErrorMessage }
    var isUpdating: Bool { pendingCount > 0 }
    var onMemoryUpdated: (() async -> Void)?
    var onWorkFinished: (() -> Void)?

    private let store: MarkdownMemoryStore
    private let conversations: ConversationRepository
    private let consolidator: ChatMemoryConsolidator
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var jobs: [UUID: Task<Void, Never>] = [:]

    init(store: MarkdownMemoryStore, conversations: ConversationRepository) {
        self.store = store
        self.conversations = conversations
        self.consolidator = ChatMemoryConsolidator(store: store)
    }

    func promptContext(query: String, maximumUTF8Bytes: Int) async -> String {
        do {
            let context = try await store.sharedPromptMemory(
                query: query, maximumUTF8Bytes: maximumUTF8Bytes
            )
            readErrorMessage = nil
            return context
        } catch {
            readErrorMessage = String(localized: "共享记忆暂不可用：\(error.localizedDescription)")
            return ""
        }
    }

    func enqueue(
        userMessage: AgentMessage,
        responseMessageID: UUID,
        conversationID: UUID,
        model: ModelOption,
        apiKey: String,
        client: any AgentChatCompleting
    ) {
        let jobID = UUID()
        let previous = tail
        pendingCount += 1
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                jobs[jobID] = nil
                pendingCount -= 1
                if pendingCount == 0 { tail = nil }
                onWorkFinished?()
            }
            guard !Task.isCancelled,
                  sourceIsCurrent(userMessage, conversationID: conversationID) else { return }
            let lease = BackgroundExecutionController.shared.begin { [weak self] in
                self?.jobs[jobID]?.cancel()
            }
            defer { BackgroundExecutionController.shared.end(lease) }
            do {
                let result = try await consolidator.consolidate(
                    userMessages: [userMessage],
                    client: client,
                    model: model.id,
                    apiKey: apiKey,
                    contextWindow: model.contextWindow,
                    maxTokens: model.maxOutputTokens,
                    onResponseUsage: { [weak self] usage in
                        try await self?.recordUsage(
                            usage, responseMessageID: responseMessageID, conversationID: conversationID
                        )
                    },
                    shouldPersist: { [weak self] in
                        await self?.sourceIsCurrent(userMessage, conversationID: conversationID) ?? false
                    }
                )
                consolidationErrorMessage = nil
                if result.longTermAdded > 0 || result.dailyAdded > 0 {
                    await onMemoryUpdated?()
                }
            } catch is CancellationError {
                consolidationErrorMessage = String(localized: "共享记忆整理已中断，本次回复不受影响。")
            } catch {
                consolidationErrorMessage = String(localized: "聊天已完成，但共享记忆未更新：\(error.localizedDescription)")
            }
        }
        jobs[jobID] = task
        tail = task
    }

    func waitUntilIdle() async {
        while let task = tail { await task.value }
    }

    private func recordUsage(
        _ usage: AgentUsage, responseMessageID: UUID, conversationID: UUID
    ) throws {
        try conversations.appendMemoryUsage(usage, toMessageID: responseMessageID, in: conversationID)
    }

    private func sourceIsCurrent(_ message: AgentMessage, conversationID: UUID) -> Bool {
        guard let conversation = conversations.conversation(id: conversationID),
              conversation.mode == .chat,
              let source = conversation.messages.first(where: { $0.id == message.id }) else { return false }
        return source.role == .user && source.content == message.content
    }
}
