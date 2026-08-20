import Foundation

nonisolated public struct MarkdownMemoryLimits: Equatable, Sendable {
    public let maximumLongTermFileBytes: Int
    public let maximumDailyFileBytes: Int
    public let maximumDailyFileCount: Int
    public let maximumDailyTotalBytes: Int
    public let maximumHarnessFailureFileBytes: Int

    public init(
        maximumLongTermFileBytes: Int,
        maximumDailyFileBytes: Int,
        maximumDailyFileCount: Int,
        maximumDailyTotalBytes: Int,
        maximumHarnessFailureFileBytes: Int = 256 * 1_024
    ) {
        precondition(maximumLongTermFileBytes > 0)
        precondition(maximumDailyFileBytes > 0)
        precondition(maximumDailyFileCount > 0)
        precondition(maximumDailyTotalBytes > 0)
        precondition(maximumHarnessFailureFileBytes > 0)
        self.maximumLongTermFileBytes = maximumLongTermFileBytes
        self.maximumDailyFileBytes = maximumDailyFileBytes
        self.maximumDailyFileCount = maximumDailyFileCount
        self.maximumDailyTotalBytes = maximumDailyTotalBytes
        self.maximumHarnessFailureFileBytes = maximumHarnessFailureFileBytes
    }

    public static let `default` = MarkdownMemoryLimits(
        maximumLongTermFileBytes: 1 * 1024 * 1024,
        maximumDailyFileBytes: 512 * 1024,
        maximumDailyFileCount: 730,
        maximumDailyTotalBytes: 16 * 1024 * 1024,
        maximumHarnessFailureFileBytes: 256 * 1_024
    )
}
