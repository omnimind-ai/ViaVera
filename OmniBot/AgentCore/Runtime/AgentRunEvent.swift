import Foundation

nonisolated public enum AgentRunEvent: Sendable {
    case started(runID: UUID)
    case requestStarted(round: Int, attempt: Int)
    case assistantMessageStarted(id: UUID, round: Int)
    case assistantMessageUpdated(id: UUID, snapshot: AgentStreamSnapshot, round: Int)
    case assistantMessage(AgentMessage, usage: AgentUsage, contextWindow: Int?, round: Int)
    case toolStarted(AgentToolCall, round: Int)
    case toolCompleted(AgentToolCall, result: AgentToolExecutionResult, round: Int)
    case retrying(round: Int, nextAttempt: Int, errorDescription: String)
    case completed(AgentRunResult)
    case cancelled(runID: UUID)
}

public typealias AgentRunEventHandler = @Sendable (AgentRunEvent) async throws -> Void
