import Foundation

nonisolated public enum MemorySource: Codable, Hashable, Sendable {
    case longTerm
    case daily(date: String)
}
