import Foundation

nonisolated enum AgentReasoningContent {
    static let maximumPersistedCharacters = 16 * 1_024
    static let truncationNotice = "[Earlier reasoning omitted]\n"

    static func boundedForPersistence(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard value.count > maximumPersistedCharacters else { return value }

        let bodyLimit = max(0, maximumPersistedCharacters - truncationNotice.count)
        return truncationNotice + String(value.suffix(bodyLimit))
    }
}
