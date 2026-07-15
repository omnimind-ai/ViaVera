import Foundation

nonisolated public struct AgentChatRequest: Codable, Hashable, Sendable {
    public let runID: UUID
    public let model: String
    public let messages: [AgentMessage]
    public let tools: [AgentToolDefinition]
    public let temperature: Double?
    public let maxTokens: Int?
    public let reasoningEffort: AgentReasoningEffort?
    public let stream: Bool

    public init(
        runID: UUID,
        model: String,
        messages: [AgentMessage],
        tools: [AgentToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        reasoningEffort: AgentReasoningEffort? = nil,
        stream: Bool = false
    ) {
        self.runID = runID
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
        self.stream = stream
    }
}
