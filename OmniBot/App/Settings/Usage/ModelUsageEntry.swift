import Foundation

/// A lightweight snapshot: analytics never needs message content or tool payloads.
nonisolated struct ModelUsageEntry: Sendable {
    let date: Date
    let role: String
    let status: String
    let modelID: String?
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cachedTokens: Int = 0
    var cacheCreationTokens: Int = 0

    var isModelResponse: Bool {
        role == "assistant" && (
            status == "completed" || inputTokens > 0 || outputTokens > 0 || cachedTokens > 0
        )
    }
}
