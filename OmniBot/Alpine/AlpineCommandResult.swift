import Foundation

struct AlpineCommandResult: Sendable {
    let executionID: UUID
    let processIdentifier: Int
    let exitCode: Int
    let standardOutput: String
    let standardError: String
    let duration: Duration
    let failureDescription: String?

    var succeeded: Bool {
        exitCode == 0 && failureDescription == nil
    }
}
