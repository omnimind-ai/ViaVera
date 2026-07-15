import Foundation

nonisolated public enum AgentRole: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
    case tool
}
