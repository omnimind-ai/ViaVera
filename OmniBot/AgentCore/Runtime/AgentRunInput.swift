import Foundation

nonisolated public struct AgentRunInput: Sendable {
    public let runID: UUID
    public let conversationID: UUID
    public let model: String
    public let apiKey: String
    public let systemMessages: [AgentMessage]
    public let history: [AgentMessage]
    public let currentUserMessage: AgentMessage
    public let workspaceURL: URL
    public let continueMode: Bool
    public let temperature: Double?
    public let maxTokens: Int?
    public let contextWindow: Int?
    public let reasoningEffort: AgentReasoningEffort?
    public let allowsToolCalls: Bool

    public init(
        runID: UUID = UUID(),
        conversationID: UUID,
        model: String,
        apiKey: String,
        systemMessages: [AgentMessage],
        history: [AgentMessage],
        currentUserMessage: AgentMessage,
        workspaceURL: URL,
        continueMode: Bool = false,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        contextWindow: Int? = nil,
        reasoningEffort: AgentReasoningEffort? = nil,
        allowsToolCalls: Bool = true
    ) {
        self.runID = runID
        self.conversationID = conversationID
        self.model = model
        self.apiKey = apiKey
        self.systemMessages = systemMessages
        self.history = history
        self.currentUserMessage = currentUserMessage
        self.workspaceURL = workspaceURL
        self.continueMode = continueMode
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.contextWindow = contextWindow
        self.reasoningEffort = reasoningEffort
        self.allowsToolCalls = allowsToolCalls
    }
}
