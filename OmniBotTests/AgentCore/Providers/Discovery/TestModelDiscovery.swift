import Foundation

@testable import Via_Vera

nonisolated struct TestModelDiscovery: ModelDiscovering {
    let result: ModelDiscoveryResult

    func discoverModels(
        for profile: ProviderProfile,
        apiKey: String
    ) async throws -> ModelDiscoveryResult {
        result
    }
}
