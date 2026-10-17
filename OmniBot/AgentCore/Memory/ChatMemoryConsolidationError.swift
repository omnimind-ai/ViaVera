import Foundation

nonisolated public struct ChatMemoryConsolidationError: LocalizedError, Sendable {
    public let usage: AgentUsage

    public init(usage: AgentUsage) {
        self.usage = usage
    }

    public var errorDescription: String? {
        String(localized: "模型未返回有效的记忆整理结果。")
    }
}
