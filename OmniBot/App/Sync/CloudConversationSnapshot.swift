import Foundation
import SwiftData

nonisolated struct CloudConversationSnapshot: Codable, Sendable {
    var id: UUID
    var title: String
    var providerID: String?
    var modelID: String
    var status: String
    var contextSummary: String?
    var contextCutoffSequence: Int?
    var reasoningEffort: String?
    var lastErrorMessage: String?
    var usage: AgentUsage
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var messages: [CloudMessageSnapshot]

    @MainActor init(_ conversation: ConversationRecord) throws {
        id = conversation.id
        title = conversation.title
        providerID = conversation.providerID
        modelID = conversation.modelID
        status = conversation.statusRawValue
        contextSummary = conversation.contextSummary
        contextCutoffSequence = conversation.contextCutoffSequence
        reasoningEffort = conversation.reasoningEffortRawValue
        lastErrorMessage = conversation.lastErrorMessage
        usage = conversation.usage
        isPinned = conversation.isPinned
        createdAt = conversation.createdAt
        updatedAt = conversation.updatedAt
        messages = try conversation.orderedMessages.map(CloudMessageSnapshot.init)
    }

    @MainActor func apply(to conversation: ConversationRecord, context: ModelContext) throws {
        guard id == conversation.id, Set(messages.map(\.message.id)).count == messages.count else {
            throw CloudSyncError.invalidData
        }
        // Build all payloads before mutating relationships, so decoding failure
        // cannot partially replace a transcript.
        let incoming = try messages.map { try $0.record() }
        conversation.title = title
        conversation.providerID = providerID
        conversation.modelID = modelID
        conversation.statusRawValue = status == ConversationStatus.running.rawValue
            ? ConversationStatus.failed.rawValue : status
        conversation.contextSummary = contextSummary
        conversation.contextCutoffSequence = contextCutoffSequence
        conversation.reasoningEffortRawValue = reasoningEffort
        conversation.lastErrorMessage = status == ConversationStatus.running.rawValue
            ? ConversationRepository.interruptedRunMessage : lastErrorMessage
        conversation.usage = usage
        conversation.isPinned = isPinned
        conversation.createdAt = createdAt
        conversation.updatedAt = updatedAt

        // Update existing IDs in place; deleting then reinserting a unique
        // SwiftData ID within one transaction can resurrect stale relationships.
        let existing = Dictionary(uniqueKeysWithValues: conversation.messages.map { ($0.id, $0) })
        let wanted = Set(incoming.map(\.id))
        for old in conversation.messages where !wanted.contains(old.id) { context.delete(old) }
        conversation.messages = try incoming.map { record in
            guard let old = existing[record.id] else { return record }
            try old.replacePayload(with: record.decodeMessage(), status: record.status,
                                   updatedAt: record.updatedAt)
            old.sequence = record.sequence
            old.contextWindow = record.contextWindow
            old.promptTokens = record.promptTokens
            old.completionTokens = record.completionTokens
            old.cachedTokens = record.cachedTokens
            old.cacheCreationTokens = record.cacheCreationTokens
            old.reportsCacheUsage = record.reportsCacheUsage
            old.modelID = record.modelID
            old.providerID = record.providerID
            old.createdAt = record.createdAt
            return old
        }
    }
}

nonisolated struct CloudMessageSnapshot: Codable, Sendable {
    var message: AgentMessage
    var sequence: Int
    var status: String
    var contextWindow: Int?
    var usage: AgentUsage
    var modelID: String?
    var providerID: String?
    var createdAt: Date
    var updatedAt: Date

    @MainActor init(_ record: MessageRecord) throws {
        message = try record.decodeMessage()
        sequence = record.sequence
        status = record.statusRawValue
        contextWindow = record.contextWindow
        usage = AgentUsage(promptTokens: record.promptTokens, completionTokens: record.completionTokens,
                           totalTokens: 0, cachedTokens: record.cachedTokens,
                           cacheCreationTokens: record.cacheCreationTokens, reportsCacheUsage: record.reportsCacheUsage)
        modelID = record.modelID
        providerID = record.providerID
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    @MainActor func record() throws -> MessageRecord {
        let record = try MessageRecord(message: message, sequence: sequence,
                                       status: MessageStatus(rawValue: status) ?? .completed,
                                       usage: usage, contextWindow: contextWindow,
                                       createdAt: createdAt, updatedAt: updatedAt)
        record.modelID = modelID
        record.providerID = providerID
        if record.status == .streaming || record.status == .pending { record.status = .interrupted }
        return record
    }
}
