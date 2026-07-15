import Foundation

nonisolated struct OmniActiveTerminalCommand: Sendable {
    let runID: UUID
    let callID: String
    let sessionID: UUID?
    let task: Task<OmniTerminalCommandResult, Error>
}
