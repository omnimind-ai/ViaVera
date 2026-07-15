import Foundation

nonisolated public enum ConversationStatus: String, Codable, Hashable, Sendable {
    case idle
    case running
    case completed
    case failed
    case cancelled
}
