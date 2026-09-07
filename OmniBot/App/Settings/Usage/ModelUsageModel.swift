import Foundation

nonisolated struct ModelUsageModel: Identifiable, Sendable {
    /// A missing identifier stays unknown rather than inheriting a conversation's current model.
    let modelID: String?
    var responseCount = 0
    var totalTokens = 0

    var id: String { modelID.map { "model:\($0)" } ?? "unknown" }
    var title: String { modelID ?? "未记录模型" }
}
