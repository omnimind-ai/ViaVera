import Foundation

nonisolated public struct ResolvedAgentSkill: Hashable, Sendable {
    public let entry: AgentSkillIndexEntry
    public let frontmatter: [String: String]
    public let bodyMarkdown: String
    public let referencePaths: [String]
    public let scriptsPath: String?
    public let assetsPath: String?
    public let triggerReason: String

    public func promptSummary(maximumCharacters: Int = 8_000) -> String {
        var sections = [
            "Skill: \(entry.name) (id=\(entry.id))",
            "Trigger: \(triggerReason)",
            "SKILL.md: \(entry.skillFilePath)",
        ]
        if let scriptsPath { sections.append("Scripts: \(scriptsPath)") }
        if let assetsPath { sections.append("Assets: \(assetsPath)") }
        if !referencePaths.isEmpty {
            sections.append("References: \(referencePaths.joined(separator: ", "))")
        }
        sections.append(bodyMarkdown)
        let value = sections.joined(separator: "\n")
        guard value.count > maximumCharacters else { return value }
        return String(value.prefix(maximumCharacters)) + "\n…[skill truncated]"
    }
}
