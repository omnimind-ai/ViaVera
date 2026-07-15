import Foundation

/// Non-secret configuration for a model-provider endpoint.
///
/// API keys intentionally do not belong to this value. Store them with
/// `APIKeyStoring`, keyed by this profile's `id`.
nonisolated public struct ProviderProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var protocolType: ProviderProtocolType
    public var wireAPI: WireAPI
    public var defaultHeaders: [String: String]
    public var models: [ModelOption]
    public var isEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: URL,
        protocolType: ProviderProtocolType = .openAICompatible,
        wireAPI: WireAPI = .chatCompletions,
        defaultHeaders: [String: String] = [:],
        models: [ModelOption] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.protocolType = protocolType
        self.wireAPI = wireAPI
        self.defaultHeaders = defaultHeaders
        self.models = models
        self.isEnabled = isEnabled
    }

    /// Stable Keychain account name. The value itself is not a secret.
    public var apiKeyAccount: String {
        "provider.\(id)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case baseURL
        case protocolType
        case wireAPI
        case defaultHeaders
        case models
        case isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        protocolType = try container.decodeIfPresent(
            ProviderProtocolType.self,
            forKey: .protocolType
        ) ?? .openAICompatible
        wireAPI = try container.decodeIfPresent(WireAPI.self, forKey: .wireAPI)
            ?? .chatCompletions
        defaultHeaders = try container.decodeIfPresent(
            [String: String].self,
            forKey: .defaultHeaders
        ) ?? [:]
        models = try container.decodeIfPresent([ModelOption].self, forKey: .models) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}
