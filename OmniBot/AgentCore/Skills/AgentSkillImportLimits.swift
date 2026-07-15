import Foundation

nonisolated public struct AgentSkillImportLimits: Hashable, Sendable {
    public static let `default` = AgentSkillImportLimits(
        maximumFileCount: 2_048,
        maximumTotalBytes: 64 * 1_024 * 1_024,
        maximumFileBytes: 16 * 1_024 * 1_024,
        maximumSkillFileBytes: 256 * 1_024
    )

    public let maximumFileCount: Int
    public let maximumTotalBytes: Int64
    public let maximumFileBytes: Int64
    public let maximumSkillFileBytes: Int

    public init(
        maximumFileCount: Int,
        maximumTotalBytes: Int64,
        maximumFileBytes: Int64,
        maximumSkillFileBytes: Int
    ) {
        self.maximumFileCount = max(1, maximumFileCount)
        self.maximumTotalBytes = max(1, maximumTotalBytes)
        self.maximumFileBytes = max(1, maximumFileBytes)
        self.maximumSkillFileBytes = max(1, maximumSkillFileBytes)
    }
}
