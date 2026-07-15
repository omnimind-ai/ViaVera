import Foundation

nonisolated public struct OmniTerminalCommandRequest: Hashable, Sendable {
    public let command: String
    public let workingDirectory: String
    public let environment: [String: String]
    public let timeout: Duration

    public init(
        command: String,
        workingDirectory: String = "/workspace",
        environment: [String: String] = [:],
        timeout: Duration = .seconds(120)
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }
}
