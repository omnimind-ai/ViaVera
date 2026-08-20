import Foundation

nonisolated public struct AgentChatRequest: Codable, Hashable, Sendable {
    public let runID: UUID
    public let model: String
    public let messages: [AgentMessage]
    public let tools: [AgentToolDefinition]
    public let temperature: Double?
    public let maxTokens: Int?
    public let reasoningEffort: AgentReasoningEffort?
    public let promptCacheKey: String?
    public let stream: Bool

    public init(
        runID: UUID,
        model: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        reasoningEffort: AgentReasoningEffort? = nil,
        promptCacheKey: String? = nil,
        stream: Bool = false
    ) {
        self.runID = runID
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
        self.promptCacheKey = promptCacheKey
        self.stream = stream
    }

    /// A stable, anonymous routing key shared by all model rounds in one
    /// conversation. It intentionally contains no account or device identity.
    public static func promptCacheKey(conversationID: UUID) -> String {
        "omnibot:v1:conversation:\(conversationID.uuidString.lowercased())"
    }

    func replacingPromptCacheKey(_ value: String?) -> AgentChatRequest {
        AgentChatRequest(
            runID: runID,
            model: model,
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoningEffort: reasoningEffort,
            promptCacheKey: value,
            stream: stream
        )
    }
}
