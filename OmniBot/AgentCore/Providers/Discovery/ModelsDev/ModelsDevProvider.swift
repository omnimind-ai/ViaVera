import Foundation

nonisolated struct ModelsDevProvider: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    // Some catalog entries use environment-variable templates that are not
    // valid Foundation URLs, so keep the source value losslessly.
    let api: String?
    let models: [String: ModelsDevModel]
}
