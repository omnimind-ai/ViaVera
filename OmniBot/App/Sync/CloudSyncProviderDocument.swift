import Foundation

/// A provider and its credential travel as one version, so a key can never be
/// rebound to a different endpoint by merging metadata and secrets separately.
nonisolated struct CloudSyncProviderDocument: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let profile: ProviderProfile
    let credential: Credential?

    struct Credential: Codable, Equatable, Sendable {
        let apiKey: String
        let endpointBinding: String
    }
}
