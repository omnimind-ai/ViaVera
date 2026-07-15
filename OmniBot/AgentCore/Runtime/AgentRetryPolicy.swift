import Foundation

nonisolated public struct AgentRetryPolicy: Hashable, Sendable {
    public let maxAttempts: Int
    public let initialDelayNanoseconds: UInt64
    public let multiplier: Double

    public init(
        maxAttempts: Int = 3,
        initialDelayNanoseconds: UInt64 = 500_000_000,
        multiplier: Double = 2
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.multiplier = max(1, multiplier)
    }

    public static let `default` = AgentRetryPolicy()

    public func delayNanoseconds(beforeAttempt attempt: Int) -> UInt64 {
        guard attempt > 1 else { return 0 }
        let exponent = Double(attempt - 2)
        let value = Double(initialDelayNanoseconds) * pow(multiplier, exponent)
        return UInt64(min(value, Double(UInt64.max)))
    }
}
