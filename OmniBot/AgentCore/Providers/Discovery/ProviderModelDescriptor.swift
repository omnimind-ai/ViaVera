import Foundation

nonisolated struct ProviderModelDescriptor: Decodable, Equatable, Sendable {
    let id: String
    let ownedBy: String?
}
