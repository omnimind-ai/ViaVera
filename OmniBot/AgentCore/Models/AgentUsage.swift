import Foundation

nonisolated public struct AgentUsage: Codable, Hashable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cachedTokens: Int

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        cachedTokens: Int = 0
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
    }

    public static let zero = AgentUsage(
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
        cachedTokens: 0
    )

    public static func + (lhs: AgentUsage, rhs: AgentUsage) -> AgentUsage {
        AgentUsage(
            promptTokens: saturatingSum(lhs.promptTokens, rhs.promptTokens),
            completionTokens: saturatingSum(lhs.completionTokens, rhs.completionTokens),
            totalTokens: saturatingSum(lhs.totalTokens, rhs.totalTokens),
            cachedTokens: saturatingSum(lhs.cachedTokens, rhs.cachedTokens)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case promptTokens
        case completionTokens
        case totalTokens
        case cachedTokens
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        cachedTokens = try container.decodeIfPresent(Int.self, forKey: .cachedTokens) ?? 0
    }

    static func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? .max : .min
    }
}
