import Foundation
import SwiftData

@Model
public final class ConversationRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var providerID: String?
    public var modelID: String
    public var statusRawValue: String
    public var contextSummary: String?
    public var contextCutoffSequence: Int?
    public var reasoningEffortRawValue: String?
    public var lastErrorMessage: String?
    public var promptTokens: Int = 0
    public var completionTokens: Int = 0
    public var totalTokens: Int = 0
    public var cachedTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var reportsCacheUsage: Bool = false
    public var isPinned: Bool = false
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    public var messages: [MessageRecord]

    public init(
        id: UUID = UUID(),
        title: String = "New conversation",
        providerID: String? = nil,
        modelID: String,
        status: ConversationStatus = .idle,
        contextSummary: String? = nil,
        contextCutoffSequence: Int? = nil,
        reasoningEffort: AgentReasoningEffort? = nil,
        lastErrorMessage: String? = nil,
        usage: AgentUsage = .zero,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [MessageRecord] = []
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.modelID = modelID
        self.statusRawValue = status.rawValue
        self.contextSummary = contextSummary
        self.contextCutoffSequence = contextCutoffSequence
        self.reasoningEffortRawValue = reasoningEffort?.rawValue
        self.lastErrorMessage = lastErrorMessage
        self.promptTokens = usage.promptTokens
        self.completionTokens = usage.completionTokens
        self.totalTokens = usage.totalTokens
        self.cachedTokens = usage.cachedTokens
        self.cacheCreationTokens = usage.cacheCreationTokens
        self.reportsCacheUsage = usage.reportsCacheUsage
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    public var status: ConversationStatus {
        get { ConversationStatus(rawValue: statusRawValue) ?? .idle }
        set { statusRawValue = newValue.rawValue }
    }

    public var reasoningEffort: AgentReasoningEffort? {
        get { reasoningEffortRawValue.flatMap(AgentReasoningEffort.init(rawValue:)) }
        set { reasoningEffortRawValue = newValue?.rawValue }
    }

    public var orderedMessages: [MessageRecord] {
        messages.sorted {
            if $0.sequence == $1.sequence { return $0.createdAt < $1.createdAt }
            return $0.sequence < $1.sequence
        }
    }

    public var usage: AgentUsage {
        get {
            AgentUsage(
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedTokens: cachedTokens,
                cacheCreationTokens: cacheCreationTokens,
                reportsCacheUsage: reportsCacheUsage
                    || cachedTokens > 0
                    || cacheCreationTokens > 0
            )
        }
        set {
            promptTokens = newValue.promptTokens
            completionTokens = newValue.completionTokens
            totalTokens = newValue.totalTokens
            cachedTokens = newValue.cachedTokens
            cacheCreationTokens = newValue.cacheCreationTokens
            reportsCacheUsage = newValue.reportsCacheUsage
        }
    }

    @discardableResult
    public func append(
        _ message: AgentMessage,
        status: MessageStatus = .completed,
        usage: AgentUsage = .zero,
        contextWindow: Int? = nil,
        createdAt: Date = Date()
    ) throws -> MessageRecord {
        let record = try MessageRecord(
            message: message,
            sequence: (messages.map(\.sequence).max() ?? -1) + 1,
            status: status,
            usage: usage,
            contextWindow: contextWindow,
            createdAt: createdAt,
            conversation: self
        )
        messages.append(record)
        updatedAt = createdAt
        return record
    }
}
