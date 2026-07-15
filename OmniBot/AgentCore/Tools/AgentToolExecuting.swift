import Foundation

/// Implemented by host tool layers, including the future iSH-backed Alpine runtime.
nonisolated public protocol AgentToolExecuting: Sendable {
    func availableTools() async -> [AgentToolDefinition]

    func execute(
        _ call: AgentToolCall,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult

    /// Requests cancellation of the tool that is currently executing for a run.
    /// Unlike `cancel(runID:)`, this must not cancel the surrounding Agent loop.
    func cancelCurrentTool(runID: UUID, callID: String) async -> Bool

    func cancel(runID: UUID) async
}

public extension AgentToolExecuting {
    func cancelCurrentTool(runID: UUID, callID: String) async -> Bool { false }

    func cancel(runID: UUID) async {}
}
