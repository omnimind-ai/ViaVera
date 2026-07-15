import Foundation

nonisolated public struct AgentSystemPromptContext: Sendable {
    public let soul: String
    public let memory: MemoryPromptContext
    public let relevantMemories: [MemorySearchHit]
    public let workspacePath: String
    public let workspace: AgentWorkspaceDescriptor
    public let installedSkills: [AgentSkillIndexEntry]
    public let resolvedSkills: [ResolvedAgentSkill]
    public let availableToolNames: [String]
    public let platformName: String
    public let now: Date
    public let timeZone: TimeZone
    public let localeIdentifier: String

    public init(
        soul: String,
        memory: MemoryPromptContext,
        relevantMemories: [MemorySearchHit] = [],
        workspacePath: String = "/workspace",
        workspace: AgentWorkspaceDescriptor? = nil,
        installedSkills: [AgentSkillIndexEntry] = [],
        resolvedSkills: [ResolvedAgentSkill] = [],
        availableToolNames: [String] = [],
        platformName: String = AgentSystemPromptContext.currentPlatformName,
        now: Date = .now,
        timeZone: TimeZone = .current,
        localeIdentifier: String = Locale.current.identifier
    ) {
        self.soul = soul
        self.memory = memory
        self.relevantMemories = relevantMemories
        self.workspacePath = workspacePath
        self.workspace = workspace ?? AgentWorkspaceDescriptor(
            id: "shared",
            rootPath: workspacePath,
            currentWorkingDirectory: workspacePath
        )
        self.installedSkills = installedSkills
        self.resolvedSkills = resolvedSkills
        self.availableToolNames = availableToolNames
        self.platformName = platformName
        self.now = now
        self.timeZone = timeZone
        self.localeIdentifier = localeIdentifier
    }

    public static var currentPlatformName: String {
#if os(iOS)
        "iOS"
#elseif os(macOS)
        "macOS"
#else
        "Apple platform"
#endif
    }
}
