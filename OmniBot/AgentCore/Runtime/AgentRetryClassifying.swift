import Foundation

nonisolated public protocol AgentRetryClassifying: Error {
    var isRetryable: Bool { get }
}
