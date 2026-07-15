import Foundation

nonisolated public protocol AgentChatCompleting: Sendable {
    func complete(_ request: AgentChatRequest, apiKey: String) async throws -> AgentChatResponse
    func cancel(runID: UUID) async
}

public extension AgentChatCompleting {
    func cancel(runID: UUID) async {}
}
