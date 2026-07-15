import Foundation

/// A cumulative, safe-to-display provider stream snapshot.
nonisolated public struct AgentStreamSnapshot: Equatable, Sendable {
    public var content: String
    public var reasoningContent: String

    public init(content: String = "", reasoningContent: String = "") {
        self.content = content
        self.reasoningContent = reasoningContent
    }

    public var isEmpty: Bool {
        content.isEmpty && reasoningContent.isEmpty
    }
}
