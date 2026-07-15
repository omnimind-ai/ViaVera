import Foundation

struct TurnUsagePresentation: Equatable {
    let contextTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int

    init(usage: AgentUsage) {
        contextTokens = AgentUsage.saturatingSum(
            usage.promptTokens,
            usage.cachedTokens
        )
        inputTokens = usage.promptTokens
        outputTokens = usage.completionTokens
        cachedTokens = usage.cachedTokens
    }

    var isEmpty: Bool {
        contextTokens <= 0
            && inputTokens <= 0
            && outputTokens <= 0
            && cachedTokens <= 0
    }
}
