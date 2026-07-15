import Foundation

nonisolated public struct OmniTerminalCommandResult: Hashable, Sendable {
    public let executionID: UUID
    public let processIdentifier: Int
    public let exitCode: Int
    public let standardOutput: String
    public let standardError: String
    public let duration: Duration
    public let failureDescription: String?

    public init(
        executionID: UUID = UUID(),
        processIdentifier: Int = -1,
        exitCode: Int,
        standardOutput: String = "",
        standardError: String = "",
        duration: Duration = .zero,
        failureDescription: String? = nil
    ) {
        self.executionID = executionID
        self.processIdentifier = processIdentifier
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.duration = duration
        self.failureDescription = failureDescription
    }

    public var succeeded: Bool {
        exitCode == 0 && failureDescription == nil
    }
}
