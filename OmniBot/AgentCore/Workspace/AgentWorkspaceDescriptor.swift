import Foundation

nonisolated public struct AgentWorkspaceDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let rootPath: String
    public let currentWorkingDirectory: String
    public let resourceRoot: String
    public let attachmentsPath: String
    public let skillsPath: String
    public let browserPath: String
    public let offloadsPath: String
    public let retentionPolicy: String

    public init(
        id: String,
        rootPath: String = "/workspace",
        currentWorkingDirectory: String = "/workspace",
        resourceRoot: String = "omnibot://workspace",
        attachmentsPath: String = "/workspace/.omnibot/attachments",
        skillsPath: String = "/workspace/.omnibot/skills",
        browserPath: String = "/workspace/.omnibot/browser",
        offloadsPath: String = "/workspace/.omnibot/offloads",
        retentionPolicy: String = "shared_root"
    ) {
        self.id = id
        self.rootPath = rootPath
        self.currentWorkingDirectory = currentWorkingDirectory
        self.resourceRoot = resourceRoot
        self.attachmentsPath = attachmentsPath
        self.skillsPath = skillsPath
        self.browserPath = browserPath
        self.offloadsPath = offloadsPath
        self.retentionPolicy = retentionPolicy
    }
}
