import Foundation

nonisolated public struct MemorySearchHit: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let source: MemorySource
    public let score: Double

    public init(id: String, text: String, source: MemorySource, score: Double) {
        self.id = id
        self.text = text
        self.source = source
        self.score = score
    }
}
