import Foundation

nonisolated public protocol AgentChatStreaming: AgentChatCompleting {
    /// Delivers cumulative safe-to-display reasoning and answer snapshots.
    func stream(
        _ request: AgentChatRequest,
        apiKey: String,
        onSnapshot: @escaping @Sendable (AgentStreamSnapshot) async throws -> Void
    ) async throws -> AgentChatResponse
}
