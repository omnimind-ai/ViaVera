import Foundation

nonisolated public struct MemoryPromptContext: Codable, Hashable, Sendable {
    public let longTermMemory: String
    public let todayMemory: String

    public init(longTermMemory: String, todayMemory: String) {
        self.longTermMemory = longTermMemory
        self.todayMemory = todayMemory
    }
}
