import Foundation

nonisolated public struct ChatMemoryConsolidationResult: Sendable, Equatable {
    public let usage: AgentUsage
    public let didRequestExtraction: Bool
    public let longTermAdded: Int
    public let dailyAdded: Int

    public init(
        usage: AgentUsage = .zero,
        didRequestExtraction: Bool = false,
        longTermAdded: Int = 0,
        dailyAdded: Int = 0
    ) {
        self.usage = usage
        self.didRequestExtraction = didRequestExtraction
        self.longTermAdded = longTermAdded
        self.dailyAdded = dailyAdded
    }
}
