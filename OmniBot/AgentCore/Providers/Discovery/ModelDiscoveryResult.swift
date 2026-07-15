import Foundation

nonisolated struct ModelDiscoveryResult: Equatable, Sendable {
    let models: [ModelOption]
    let notice: String?
}
