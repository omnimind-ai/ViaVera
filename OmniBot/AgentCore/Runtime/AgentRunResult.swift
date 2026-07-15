import Foundation

nonisolated public struct AgentRunResult: Sendable {
    public let runID: UUID
    public let finalMessage: AgentMessage
    public let messages: [AgentMessage]
    public let usage: AgentUsage
    public let rounds: Int
    public let toolExecutionCount: Int

    public init(
        runID: UUID,
        finalMessage: AgentMessage,
        messages: [AgentMessage],
        usage: AgentUsage,
        rounds: Int,
        toolExecutionCount: Int
    ) {
        self.runID = runID
        self.finalMessage = finalMessage
        self.messages = messages
        self.usage = usage
        self.rounds = rounds
        self.toolExecutionCount = toolExecutionCount
    }
}
