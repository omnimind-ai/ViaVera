import Foundation
import SwiftData

@Model
public final class MessageRecord {
    @Attribute(.unique) public var id: UUID
    public var sequence: Int
    public var roleRawValue: String
    public var content: String?
    public var toolCallID: String?
    public var toolName: String?
    /// The complete AgentMessage payload, including assistant tool calls and tool results.
    public var payloadData: Data
    public var statusRawValue: String
    public var contextWindow: Int?
    public var promptTokens: Int = 0
    public var completionTokens: Int = 0
    public var cachedTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var reportsCacheUsage: Bool = false
    /// Capture attribution when the message is created; conversation selection can change later.
    /// Nil on older records means the original model was not recorded.
    public var modelID: String?
    public var providerID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var conversation: ConversationRecord?

    public init(
        message: AgentMessage,
        sequence: Int,
        status: MessageStatus = .completed,
        usage: AgentUsage = .zero,
        contextWindow: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        conversation: ConversationRecord? = nil,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        self.id = message.id
        self.sequence = sequence
        self.roleRawValue = message.role.rawValue
        self.content = message.content
        self.toolCallID = message.toolCallID
        self.toolName = message.name
        self.payloadData = try encoder.encode(message)
        self.statusRawValue = status.rawValue
        self.contextWindow = contextWindow
        self.promptTokens = usage.promptTokens
        self.completionTokens = usage.completionTokens
        self.cachedTokens = usage.cachedTokens
        self.cacheCreationTokens = usage.cacheCreationTokens
        self.reportsCacheUsage = usage.reportsCacheUsage
        self.modelID = conversation?.modelID
        self.providerID = conversation?.providerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.conversation = conversation
    }

    public var role: AgentRole {
        AgentRole(rawValue: roleRawValue) ?? .assistant
    }

    public var status: MessageStatus {
        get { MessageStatus(rawValue: statusRawValue) ?? .completed }
        set { statusRawValue = newValue.rawValue }
    }

    public func decodeMessage(using decoder: JSONDecoder = JSONDecoder()) throws -> AgentMessage {
        try decoder.decode(AgentMessage.self, from: payloadData)
    }

    public func replacePayload(
        with message: AgentMessage,
        status: MessageStatus? = nil,
        usage: AgentUsage? = nil,
        contextWindow: Int? = nil,
        updatedAt: Date = Date(),
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        id = message.id
        roleRawValue = message.role.rawValue
        content = message.content
        toolCallID = message.toolCallID
        toolName = message.name
        payloadData = try encoder.encode(message)
        if let status { statusRawValue = status.rawValue }
        if let usage {
            promptTokens = usage.promptTokens
            completionTokens = usage.completionTokens
            cachedTokens = usage.cachedTokens
            cacheCreationTokens = usage.cacheCreationTokens
            reportsCacheUsage = usage.reportsCacheUsage
        }
        if let contextWindow { self.contextWindow = contextWindow }
        self.updatedAt = updatedAt
    }
}
