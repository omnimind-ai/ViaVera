import Foundation

struct TurnUsagePresentation: Equatable {
    let contextTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let cacheCreationTokens: Int
    let cacheHitPercentage: Int?

    init(usage: AgentUsage) {
        contextTokens = AgentUsage.saturatingSum(
            usage.promptTokens,
            usage.cachedTokens
        )
        inputTokens = usage.promptTokens
        outputTokens = usage.completionTokens
        cachedTokens = usage.cachedTokens
        cacheCreationTokens = usage.cacheCreationTokens
        if usage.reportsCacheUsage, contextTokens > 0 {
            let rate = Double(usage.cachedTokens) / Double(contextTokens) * 100
            cacheHitPercentage = min(100, max(0, Int(rate.rounded())))
        } else if usage.reportsCacheUsage {
            cacheHitPercentage = 0
        } else {
            cacheHitPercentage = nil
        }
    }

    var isEmpty: Bool {
        contextTokens <= 0
            && inputTokens <= 0
            && outputTokens <= 0
            && cachedTokens <= 0
            && cacheCreationTokens <= 0
    }
}
