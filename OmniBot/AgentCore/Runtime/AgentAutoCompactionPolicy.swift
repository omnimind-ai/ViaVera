import Foundation

/// Mirrors Pi/OmnibotApp's adaptive context headroom while keeping the
/// decision independent from UI and persistence.
nonisolated enum AgentAutoCompactionPolicy {
    private static let minimumReserveTokens = 2_048
    private static let maximumReserveTokens = 16_384
    private static let reserveDivisor = 8

    static func effectiveCapacity(
        configuredContextWindow: Int,
        observedContextWindow: Int?
    ) -> Int {
        let configured = max(1, configuredContextWindow)
        guard let observedContextWindow, observedContextWindow > 0 else {
            return configured
        }
        return min(configured, observedContextWindow)
    }

    static func trigger(contextCapacity: Int) -> Int {
        let capacity = max(1, contextCapacity)
        guard capacity > 1 else { return 1 }
        let adaptiveReserve = min(
            maximumReserveTokens,
            max(minimumReserveTokens, capacity / reserveDivisor)
        )
        let reserve = min(adaptiveReserve, max(1, capacity / 2))
        return max(1, capacity - reserve)
    }

    static func reportedContextTokens(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int? = nil
    ) -> Int {
        let parts = saturatingSum(max(0, promptTokens), max(0, completionTokens))
        return max(parts, max(0, totalTokens ?? 0))
    }

    static func shouldCompact(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int? = nil,
        configuredContextWindow: Int,
        observedContextWindow: Int?
    ) -> Bool {
        let capacity = effectiveCapacity(
            configuredContextWindow: configuredContextWindow,
            observedContextWindow: observedContextWindow
        )
        return reportedContextTokens(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens
        ) >= trigger(contextCapacity: capacity)
    }

    private static func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : sum
    }
}
