import Foundation

nonisolated public enum MessageStatus: String, Codable, Hashable, Sendable {
    case pending
    case streaming
    case completed
    case failed
    case interrupted
}
