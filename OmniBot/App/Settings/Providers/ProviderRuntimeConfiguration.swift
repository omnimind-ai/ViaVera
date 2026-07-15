import Foundation

nonisolated struct ProviderRuntimeConfiguration: Sendable {
    let profile: ProviderProfile
    let model: ModelOption
    let apiKey: String
}
