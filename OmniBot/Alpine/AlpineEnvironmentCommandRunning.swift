import Foundation

@MainActor
protocol AlpineEnvironmentCommandRunning: AnyObject {
    func runAlpineEnvironmentCommand(
        _ command: String,
        timeout: Duration
    ) async -> AlpineCommandResult
}

extension AlpineRuntime: AlpineEnvironmentCommandRunning {
    func runAlpineEnvironmentCommand(
        _ command: String,
        timeout: Duration
    ) async -> AlpineCommandResult {
        await execute(command, workingDirectory: "/", timeout: timeout)
    }
}
