import Foundation

/// The upstream HTTP API shape used by a provider.
nonisolated public enum WireAPI: String, Codable, CaseIterable, Sendable {
    case chatCompletions = "chat_completions"
    case responses = "responses"

    public var displayName: String {
        switch self {
        case .chatCompletions:
            "Chat Completions"
        case .responses:
            "Responses"
        }
    }
}
