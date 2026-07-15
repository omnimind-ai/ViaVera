import Foundation

nonisolated public struct AgentSkillIndexEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let compatibility: String?
    public let metadata: [String: String]
    public let rootPath: String
    public let skillFilePath: String
    public let hasScripts: Bool
    public let hasReferences: Bool
    public let hasAssets: Bool
    public let hasEvals: Bool
    public let enabled: Bool

    public var capabilities: [String] {
        var result: [String] = []
        if hasScripts { result.append("scripts") }
        if hasReferences { result.append("references") }
        if hasAssets { result.append("assets") }
        if hasEvals { result.append("evals") }
        return result
    }
}
