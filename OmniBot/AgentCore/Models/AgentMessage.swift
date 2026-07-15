import Foundation

nonisolated public struct AgentMessage: Codable, Hashable, Sendable, Identifiable {
    static let maximumPersistedProviderMetadataBytes = 128 * 1_024

    public let id: UUID
    public var role: AgentRole
    public var content: String?
    public var reasoningContent: String?
    /// Provider-owned state needed to continue a tool turn without exposing it in the UI.
    public var providerMetadata: AgentValue?
    public var toolCalls: [AgentToolCall]
    public var toolCallID: String?
    public var name: String?

    public init(
        id: UUID = UUID(),
        role: AgentRole,
        content: String? = nil,
        reasoningContent: String? = nil,
        providerMetadata: AgentValue? = nil,
        toolCalls: [AgentToolCall] = [],
        toolCallID: String? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.providerMetadata = providerMetadata
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }

    public static func system(_ content: String, id: UUID = UUID()) -> AgentMessage {
        AgentMessage(id: id, role: .system, content: content)
    }

    public static func user(_ content: String, id: UUID = UUID()) -> AgentMessage {
        AgentMessage(id: id, role: .user, content: content)
    }

    public static func assistant(
        _ content: String? = nil,
        reasoningContent: String? = nil,
        providerMetadata: AgentValue? = nil,
        toolCalls: [AgentToolCall] = [],
        id: UUID = UUID()
    ) -> AgentMessage {
        AgentMessage(
            id: id,
            role: .assistant,
            content: content,
            reasoningContent: reasoningContent,
            providerMetadata: providerMetadata,
            toolCalls: toolCalls
        )
    }

    func boundedReasoningForPersistence() -> AgentMessage {
        var copy = self
        copy.reasoningContent = AgentReasoningContent.boundedForPersistence(reasoningContent)
        if let providerMetadata,
           ((try? JSONEncoder().encode(providerMetadata).count) ?? .max)
            > Self.maximumPersistedProviderMetadataBytes {
            copy.providerMetadata = nil
        }
        return copy
    }

    public static func tool(
        callID: String,
        name: String? = nil,
        content: String,
        id: UUID = UUID()
    ) -> AgentMessage {
        AgentMessage(
            id: id,
            role: .tool,
            content: content,
            toolCallID: callID,
            name: name
        )
    }
}
