import Foundation

nonisolated public struct MarkdownMemoryLimits: Equatable, Sendable {
    public let maximumLongTermFileBytes: Int
    public let maximumDailyFileBytes: Int
    public let maximumDailyFileCount: Int
    public let maximumDailyTotalBytes: Int

    public init(
        maximumLongTermFileBytes: Int,
        maximumDailyFileBytes: Int,
        maximumDailyFileCount: Int,
        maximumDailyTotalBytes: Int
    ) {
        precondition(maximumLongTermFileBytes > 0)
        precondition(maximumDailyFileBytes > 0)
        precondition(maximumDailyFileCount > 0)
        precondition(maximumDailyTotalBytes > 0)
        self.maximumLongTermFileBytes = maximumLongTermFileBytes
        self.maximumDailyFileBytes = maximumDailyFileBytes
        self.maximumDailyFileCount = maximumDailyFileCount
        self.maximumDailyTotalBytes = maximumDailyTotalBytes
    }

    public static let `default` = MarkdownMemoryLimits(
        maximumLongTermFileBytes: 1 * 1024 * 1024,
        maximumDailyFileBytes: 512 * 1024,
        maximumDailyFileCount: 730,
        maximumDailyTotalBytes: 16 * 1024 * 1024
    )
}
