import Foundation

nonisolated public struct AgentChatResponse: Codable, Hashable, Sendable {
    public let message: AgentMessage
    public let usage: AgentUsage
    public let finishReason: String?

    public init(message: AgentMessage, usage: AgentUsage = .zero, finishReason: String? = nil) {
        self.message = message
        self.usage = usage
        self.finishReason = finishReason
    }
}
