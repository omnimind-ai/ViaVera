import Foundation

nonisolated struct OmniTerminalSession: Sendable {
    let id: UUID
    let conversationID: UUID
    var workingDirectory: String
    var environment: [String: String]
    var lastAccessAt: Date
    var lastOutput: String
    var lastExitCode: Int?
    var lastOutputWasTruncated: Bool
    var activeExecutionID: UUID?

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        workingDirectory: String,
        environment: [String: String],
        lastAccessAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.lastAccessAt = lastAccessAt
        lastOutput = ""
        lastExitCode = nil
        lastOutputWasTruncated = false
        activeExecutionID = nil
    }
}
