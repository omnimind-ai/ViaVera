import Foundation

nonisolated public struct OmniAgentToolLimits: Hashable, Sendable {
    public let maximumCommandCharacters: Int
    public let maximumCommandBytes: Int
    public let maximumTerminalOutputCharacters: Int
    public let maximumTerminalSessions: Int
    public let terminalSessionIdleTimeoutSeconds: TimeInterval
    public let maximumEnvironmentVariables: Int
    public let maximumEnvironmentKeyBytes: Int
    public let maximumEnvironmentValueBytes: Int
    public let maximumEnvironmentBytes: Int
    public let maximumReadableFileBytes: Int
    public let maximumWritableFileBytes: Int
    public let maximumListEntries: Int
    public let maximumSearchFiles: Int
    public let maximumSearchResults: Int

    public init(
        maximumCommandCharacters: Int = 64 * 1_024,
        maximumCommandBytes: Int = 64 * 1_024,
        maximumTerminalOutputCharacters: Int = 128 * 1_024,
        maximumTerminalSessions: Int = 16,
        terminalSessionIdleTimeoutSeconds: TimeInterval = 30 * 60,
        maximumEnvironmentVariables: Int = 128,
        maximumEnvironmentKeyBytes: Int = 256,
        maximumEnvironmentValueBytes: Int = 32 * 1_024,
        maximumEnvironmentBytes: Int = 64 * 1_024,
        maximumReadableFileBytes: Int = 2 * 1_024 * 1_024,
        maximumWritableFileBytes: Int = 2 * 1_024 * 1_024,
        maximumListEntries: Int = 500,
        maximumSearchFiles: Int = 2_000,
        maximumSearchResults: Int = 200
    ) {
        self.maximumCommandCharacters = max(1, maximumCommandCharacters)
        self.maximumCommandBytes = max(1, maximumCommandBytes)
        self.maximumTerminalOutputCharacters = max(1, maximumTerminalOutputCharacters)
        self.maximumTerminalSessions = max(1, maximumTerminalSessions)
        self.terminalSessionIdleTimeoutSeconds = max(0.001, terminalSessionIdleTimeoutSeconds)
        self.maximumEnvironmentVariables = max(1, maximumEnvironmentVariables)
        self.maximumEnvironmentKeyBytes = max(1, maximumEnvironmentKeyBytes)
        self.maximumEnvironmentValueBytes = max(1, maximumEnvironmentValueBytes)
        self.maximumEnvironmentBytes = max(1, maximumEnvironmentBytes)
        self.maximumReadableFileBytes = max(1, maximumReadableFileBytes)
        self.maximumWritableFileBytes = max(1, maximumWritableFileBytes)
        self.maximumListEntries = max(1, maximumListEntries)
        self.maximumSearchFiles = max(1, maximumSearchFiles)
        self.maximumSearchResults = max(1, maximumSearchResults)
    }

    public static let `default` = OmniAgentToolLimits()
}
