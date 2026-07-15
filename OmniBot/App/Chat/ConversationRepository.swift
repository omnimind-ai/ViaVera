import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationRepository {
    enum CommitRefreshOutcome: Equatable {
        case refreshed
        case committedWithoutRefresh
    }

    static let interruptedRunMessage =
        "上次 Agent 运行因应用退出或系统中断而未完成。工具结果可能未知，请检查当前状态后再重试。"

    private(set) var conversations: [ConversationRecord] = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func reload() throws {
        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        conversations = try modelContext.fetch(descriptor).sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// A process exit cannot leave a live coordinator behind. Normalize stale
    /// `.running` records in one save so the UI exposes its existing safe retry
    /// path and history repair can mark unpersisted tool outcomes as unknown.
    @discardableResult
    func recoverInterruptedRuns(at date: Date = .now) throws -> Int {
        let interrupted = conversations.filter { $0.status == .running }
        guard !interrupted.isEmpty else { return 0 }
        for conversation in interrupted {
            finalizeStreamingAssistants(in: conversation, status: .interrupted)
            conversation.status = .failed
            conversation.lastErrorMessage = Self.interruptedRunMessage
            conversation.updatedAt = date
        }
        try saveAndReload()
        return interrupted.count
    }

    @discardableResult
    func createConversation(providerID: String?, modelID: String) throws -> ConversationRecord {
        let conversation = ConversationRecord(
            title: "新任务",
            providerID: providerID,
            modelID: modelID
        )
        modelContext.insert(conversation)
        try saveAndReload()
        return conversation
    }

    func conversation(id: UUID) -> ConversationRecord? {
        conversations.first { $0.id == id }
    }

    var historyConversations: [ConversationRecord] {
        conversations.filter { !$0.messages.isEmpty }
    }

    var draftConversation: ConversationRecord? {
        conversations.first { $0.status == .idle && $0.messages.isEmpty }
    }

    func delete(_ conversation: ConversationRecord) throws {
        modelContext.delete(conversation)
        try saveAndReload()
    }

    func setPinned(_ isPinned: Bool, for conversation: ConversationRecord) throws {
        conversation.isPinned = isPinned
        try saveAndReload()
    }

    func rename(_ conversation: ConversationRecord, to title: String) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, normalizedTitle != conversation.title else { return }
        conversation.title = normalizedTitle
        try saveAndReload()
    }

    @discardableResult
    func append(
        _ message: AgentMessage,
        to conversation: ConversationRecord,
        status: MessageStatus = .completed,
        usage: AgentUsage = .zero,
        contextWindow: Int? = nil
    ) throws -> MessageRecord {
        let message = message.boundedReasoningForPersistence()
        if let existing = conversation.messages.first(where: { $0.id == message.id }) {
            try existing.replacePayload(
                with: message,
                status: status,
                usage: usage,
                contextWindow: contextWindow,
                updatedAt: .now
            )
            conversation.updatedAt = .now
            try saveAndReload()
            return existing
        }

        let record = try conversation.append(
            message,
            status: status,
            usage: usage,
            contextWindow: contextWindow,
            createdAt: .now
        )
        modelContext.insert(record)
        if message.role == .user, conversation.messages.count(where: { $0.role == .user }) == 1 {
            conversation.title = Self.title(from: message.content)
        }
        try saveAndReload()
        return record
    }

    func updateStreamingAssistant(
        id: UUID,
        snapshot: AgentStreamSnapshot,
        in conversation: ConversationRecord
    ) throws {
        let message = AgentMessage.assistant(
            snapshot.content.isEmpty ? nil : snapshot.content,
            reasoningContent: snapshot.reasoningContent.isEmpty
                ? nil
                : snapshot.reasoningContent,
            id: id
        ).boundedReasoningForPersistence()
        if let existing = conversation.messages.first(where: { $0.id == id }) {
            try existing.replacePayload(
                with: message,
                status: .streaming,
                updatedAt: .now
            )
        } else {
            let record = try conversation.append(
                message,
                status: .streaming,
                createdAt: .now
            )
            modelContext.insert(record)
        }
        conversation.updatedAt = .now
    }

    func finalizeStreamingAssistants(
        in conversation: ConversationRecord,
        status: MessageStatus
    ) {
        let streamingAssistants = conversation.messages.filter {
            $0.role == .assistant && $0.status == .streaming
        }
        for message in streamingAssistants {
            let reasoningContent = (try? message.decodeMessage())?.reasoningContent
            if Self.hasVisibleText(message.content) || Self.hasVisibleText(reasoningContent) {
                message.status = status
                message.updatedAt = .now
            } else {
                // Keep the in-memory relationship consistent immediately. SwiftData
                // does not guarantee that `delete` alone updates this collection
                // until the context is saved and refetched.
                conversation.messages.removeAll { $0.id == message.id }
                modelContext.delete(message)
            }
        }
        conversation.updatedAt = .now
    }

    private static func hasVisibleText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func updateStatus(_ status: ConversationStatus, for conversation: ConversationRecord) throws {
        conversation.status = status
        conversation.updatedAt = .now
        try saveAndReload()
    }

    func updateRunOutcome(
        status: ConversationStatus,
        errorMessage: String?,
        usage: AgentUsage,
        for conversation: ConversationRecord
    ) throws {
        conversation.status = status
        conversation.lastErrorMessage = errorMessage
        conversation.usage = usage
        conversation.updatedAt = .now
        try saveAndReload()
    }

    func updateModel(providerID: String, modelID: String, for conversation: ConversationRecord) throws {
        conversation.providerID = providerID
        conversation.modelID = modelID
        conversation.updatedAt = .now
        try saveAndReload()
    }

    func updateReasoningEffort(
        _ effort: AgentReasoningEffort,
        for conversation: ConversationRecord
    ) throws {
        conversation.reasoningEffort = effort
        conversation.updatedAt = .now
        try saveAndReload()
    }

    func contextCompactionCandidate(
        for conversation: ConversationRecord
    ) throws -> ConversationContextCompactionCandidate? {
        let lowerBound = conversation.contextCutoffSequence ?? -1
        let uncompactedRecords = conversation.orderedMessages.filter { $0.sequence > lowerBound }
        guard let latestUserIndex = uncompactedRecords.lastIndex(where: { $0.role == .user }),
              latestUserIndex > uncompactedRecords.startIndex else {
            return nil
        }

        let recordsToCompact = Array(uncompactedRecords[..<latestUserIndex])
        guard let cutoffSequence = recordsToCompact.last?.sequence else { return nil }
        let messages = try recordsToCompact.map { try $0.decodeMessage() }
        guard !messages.isEmpty else { return nil }
        return ConversationContextCompactionCandidate(
            messages: messages,
            cutoffSequence: cutoffSequence
        )
    }

    func updateContextSummary(
        _ summary: String,
        cutoffSequence: Int,
        for conversation: ConversationRecord
    ) throws {
        let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ChatCoordinatorError.emptyContextSummary }
        conversation.contextSummary = normalized
        conversation.contextCutoffSequence = cutoffSequence
        conversation.updatedAt = .now
        try saveAndReload()
    }

    @discardableResult
    func replaceLatestUserTurn(
        messageID: UUID,
        with content: String,
        in conversation: ConversationRecord,
        at date: Date = .now
    ) throws -> AgentMessage {
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContent.isEmpty else {
            throw ChatCoordinatorError.emptyRetryMessage
        }

        let orderedMessages = conversation.orderedMessages
        guard let latestUser = orderedMessages.last(where: { $0.role == .user }),
              latestUser.id == messageID else {
            throw ChatCoordinatorError.retryMessageIsNotLatest
        }

        let replacement = AgentMessage.user(normalizedContent, id: latestUser.id)
        try latestUser.replacePayload(
            with: replacement,
            status: .completed,
            usage: .zero,
            updatedAt: date
        )

        let trailingMessages = conversation.messages.filter {
            $0.sequence > latestUser.sequence
        }
        let trailingIDs = Set(trailingMessages.map(\.id))
        conversation.messages.removeAll { trailingIDs.contains($0.id) }
        for message in trailingMessages {
            modelContext.delete(message)
        }

        conversation.status = .idle
        conversation.lastErrorMessage = nil
        conversation.usage = .zero
        conversation.updatedAt = date
        if orderedMessages.prefix(while: { $0.id != latestUser.id }).allSatisfy({
            $0.role != .user
        }) {
            conversation.title = Self.title(from: normalizedContent)
        }

        try Self.commitLatestUserTurnReplacement(
            save: { try modelContext.save() },
            rollback: { modelContext.rollback() },
            reload: { try reload() }
        )
        return replacement
    }

    /// A failed save leaves the model context carrying the attempted edit and deletions.
    /// Roll those changes back and refresh the repository before surfacing the save error.
    /// Once save succeeds, however, the replacement is durable; a later fetch failure must
    /// not make callers retry an operation that has already committed.
    @discardableResult
    static func commitLatestUserTurnReplacement(
        save: () throws -> Void,
        rollback: () -> Void,
        reload: () throws -> Void
    ) throws -> CommitRefreshOutcome {
        do {
            try save()
        } catch {
            let saveError = error
            rollback()
            try? reload()
            throw saveError
        }

        do {
            try reload()
            return .refreshed
        } catch {
            return .committedWithoutRefresh
        }
    }

    func transcript(for conversation: ConversationRecord) throws -> [AgentMessage] {
        try conversation.orderedMessages.map { try $0.decodeMessage() }
    }

    func promptHistory(for conversation: ConversationRecord) throws -> [AgentMessage] {
        var history: [AgentMessage] = []
        if let summary = conversation.contextSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            history.append(ConversationContextCompaction.summaryMessage(summary))
        }
        let cutoffSequence = conversation.contextCutoffSequence ?? -1
        let recentMessages = try conversation.orderedMessages
            .filter { $0.sequence > cutoffSequence }
            .map { try $0.decodeMessage() }
        history.append(contentsOf: recentMessages)
        return history
    }

    private func saveAndReload() throws {
        try modelContext.save()
        try reload()
    }

    private static func title(from content: String?) -> String {
        let value = content?
            .split(whereSeparator: \Character.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        if value.isEmpty {
            return "新任务"
        }
        return String(value.prefix(32))
    }
}
