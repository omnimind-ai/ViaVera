import Foundation

nonisolated struct ModelUsageDay: Identifiable, Sendable {
    let date: Date
    var messageCount = 0
    var responseCount = 0
    var inputTokens = 0
    var outputTokens = 0
    var cachedTokens = 0
    var cacheCreationTokens = 0

    var id: Date { date }
    var totalTokens: Int {
        AgentUsage.saturatingSum(AgentUsage.saturatingSum(inputTokens, outputTokens), cachedTokens)
    }

    mutating func add(_ other: ModelUsageDay) {
        messageCount += other.messageCount
        responseCount += other.responseCount
        inputTokens = AgentUsage.saturatingSum(inputTokens, other.inputTokens)
        outputTokens = AgentUsage.saturatingSum(outputTokens, other.outputTokens)
        cachedTokens = AgentUsage.saturatingSum(cachedTokens, other.cachedTokens)
        cacheCreationTokens = AgentUsage.saturatingSum(cacheCreationTokens, other.cacheCreationTokens)
    }
}
