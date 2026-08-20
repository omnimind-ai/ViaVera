import Foundation

nonisolated public struct AgentUsage: Codable, Hashable, Sendable {
    /// Input tokens that were processed normally rather than read from cache.
    /// Cache writes are included here and exposed separately by
    /// `cacheCreationTokens`.
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    /// Input tokens read from a provider prompt cache.
    public let cachedTokens: Int
    /// Input tokens newly written to a provider prompt cache. This is a subset
    /// of `promptTokens`, not an additional contribution to `totalTokens`.
    public let cacheCreationTokens: Int
    /// Distinguishes an explicit zero cache hit from a provider that omitted
    /// cache accounting entirely.
    public let reportsCacheUsage: Bool

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        cachedTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        reportsCacheUsage: Bool? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reportsCacheUsage = reportsCacheUsage
            ?? (cachedTokens > 0 || cacheCreationTokens > 0)
    }

    public static let zero = AgentUsage(
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
        cachedTokens: 0,
        cacheCreationTokens: 0,
        reportsCacheUsage: false
    )

    public static func + (lhs: AgentUsage, rhs: AgentUsage) -> AgentUsage {
        AgentUsage(
            promptTokens: saturatingSum(lhs.promptTokens, rhs.promptTokens),
            completionTokens: saturatingSum(lhs.completionTokens, rhs.completionTokens),
            totalTokens: saturatingSum(lhs.totalTokens, rhs.totalTokens),
            cachedTokens: saturatingSum(lhs.cachedTokens, rhs.cachedTokens),
            cacheCreationTokens: saturatingSum(
                lhs.cacheCreationTokens,
                rhs.cacheCreationTokens
            ),
            reportsCacheUsage: lhs.reportsCacheUsage || rhs.reportsCacheUsage
        )
    }

    private enum CodingKeys: String, CodingKey {
        case promptTokens
        case completionTokens
        case totalTokens
        case cachedTokens
        case cacheCreationTokens
        case reportsCacheUsage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        cachedTokens = try container.decodeIfPresent(Int.self, forKey: .cachedTokens) ?? 0
        cacheCreationTokens = try container.decodeIfPresent(
            Int.self,
            forKey: .cacheCreationTokens
        ) ?? 0
        reportsCacheUsage = try container.decodeIfPresent(
            Bool.self,
            forKey: .reportsCacheUsage
        ) ?? (cachedTokens > 0 || cacheCreationTokens > 0)
    }

    static func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? .max : .min
    }
}
