import Foundation

nonisolated struct ConversationContextCompactionCandidate: Sendable {
    let messages: [AgentMessage]
    let cutoffSequence: Int
}
