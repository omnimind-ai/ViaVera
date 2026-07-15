import Foundation

nonisolated struct ProviderModelListResponse: Decodable, Equatable, Sendable {
    let data: [ProviderModelDescriptor]

    private enum CodingKeys: String, CodingKey {
        case data
        case models
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent(
            [ProviderModelDescriptor].self,
            forKey: .data
        ) ?? container.decode([ProviderModelDescriptor].self, forKey: .models)
    }
}
