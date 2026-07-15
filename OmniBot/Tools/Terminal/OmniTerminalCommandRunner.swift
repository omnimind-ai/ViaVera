import Foundation

nonisolated public struct OmniTerminalCommandRunner: Sendable {
    public typealias Handler = @Sendable (
        OmniTerminalCommandRequest
    ) async throws -> OmniTerminalCommandResult
    public typealias OutputHandler = @MainActor @Sendable (
        _ line: String,
        _ isStandardError: Bool
    ) -> Void
    public typealias StreamingHandler = @Sendable (
        OmniTerminalCommandRequest,
        OutputHandler?
    ) async throws -> OmniTerminalCommandResult

    private let handler: StreamingHandler

    public init(handler: @escaping Handler) {
        self.handler = { request, _ in
            try await handler(request)
        }
    }

    public init(streamingHandler: @escaping StreamingHandler) {
        handler = streamingHandler
    }

    public func execute(
        _ request: OmniTerminalCommandRequest,
        onOutput: OutputHandler? = nil
    ) async throws -> OmniTerminalCommandResult {
        try await handler(request, onOutput)
    }
}

extension OmniTerminalCommandRunner {
    @MainActor
    init(alpineRuntime: AlpineRuntime) {
        self.init(streamingHandler: { request, onOutput in
            let result = await alpineRuntime.execute(
                request.command,
                workingDirectory: request.workingDirectory,
                environment: request.environment,
                timeout: request.timeout,
                onLine: { line, isStandardError in
                    onOutput?(line, isStandardError)
                }
            )
            return OmniTerminalCommandResult(
                executionID: result.executionID,
                processIdentifier: result.processIdentifier,
                exitCode: result.exitCode,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                duration: result.duration,
                failureDescription: result.failureDescription
            )
        })
    }
}
