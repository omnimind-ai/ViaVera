import Foundation

nonisolated enum ChatComposerCommand: Equatable {
    case compact
    case showEffort
    case setEffort(AgentReasoningEffort)
    case invalidEffort

    static func parse(_ text: String) -> ChatComposerCommand? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "/compact" || normalized.hasPrefix("/compact ") {
            return .compact
        }
        if normalized == "/effort" {
            return .showEffort
        }
        guard normalized.hasPrefix("/effort ") else { return nil }
        let value = normalized.dropFirst("/effort".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let effort = AgentReasoningEffort(rawValue: value),
              AgentReasoningEffort.commandOptions.contains(effort) else {
            return .invalidEffort
        }
        return .setEffort(effort)
    }
}
