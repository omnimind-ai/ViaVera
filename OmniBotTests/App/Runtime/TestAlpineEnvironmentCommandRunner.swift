import Foundation
@testable import Via_Vera

@MainActor
final class TestAlpineEnvironmentCommandRunner: AlpineEnvironmentCommandRunning {
    var results: [AlpineCommandResult]
    private(set) var commands: [String] = []

    init(results: [AlpineCommandResult]) {
        self.results = results
    }

    func runAlpineEnvironmentCommand(
        _ command: String,
        timeout: Duration
    ) async -> AlpineCommandResult {
        commands.append(command)
        guard !results.isEmpty else {
            return AlpineCommandResult(
                executionID: UUID(),
                processIdentifier: -1,
                exitCode: -1,
                standardOutput: "",
                standardError: "",
                duration: .zero,
                failureDescription: "Missing test result"
            )
        }
        return results.removeFirst()
    }
}
