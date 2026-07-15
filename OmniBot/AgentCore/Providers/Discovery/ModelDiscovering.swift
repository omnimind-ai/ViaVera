import Foundation

nonisolated protocol ModelDiscovering: Sendable {
    func discoverModels(
        for profile: ProviderProfile,
        apiKey: String
    ) async throws -> ModelDiscoveryResult
}
