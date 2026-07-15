import Foundation

nonisolated struct ModelsDevCandidate: Sendable {
    let provider: ModelsDevProvider
    let model: ModelsDevModel
    let score: Int

    static func precedes(_ lhs: ModelsDevCandidate, _ rhs: ModelsDevCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.provider.id < rhs.provider.id
    }
}
