import Foundation

nonisolated struct ModelsDevModel: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String?
    let reasoning: Bool
    let toolCall: Bool
    let limit: ModelsDevModelLimits?
    let modalities: ModelsDevModalities?
}
