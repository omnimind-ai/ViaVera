import Foundation

nonisolated public struct AgentToolExecutionContext: Sendable {
    public let runID: UUID
    public let conversationID: UUID
    public let workspaceURL: URL

    public init(runID: UUID, conversationID: UUID, workspaceURL: URL) {
        self.runID = runID
        self.conversationID = conversationID
        self.workspaceURL = workspaceURL
    }
}
