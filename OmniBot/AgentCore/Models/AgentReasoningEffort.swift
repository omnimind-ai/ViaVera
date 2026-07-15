import Foundation

nonisolated public enum AgentReasoningEffort: String, Codable, CaseIterable, Sendable {
    case no
    case low
    case medium
    case high
    case xhigh
    case max

    public static let commandOptions: [AgentReasoningEffort] = [
        .no,
        .low,
        .high,
        .xhigh,
        .max,
    ]
}
