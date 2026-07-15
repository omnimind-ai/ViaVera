import Foundation

/// A model advertised or manually configured for a provider.
nonisolated public struct ModelOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var providerName: String?
    public var description: String?
    public var contextWindow: Int?
    public var maxOutputTokens: Int?
    public var supportsTools: Bool
    public var supportsReasoning: Bool
    public var modalities: [String]
    public var isHidden: Bool
    public var modelsDevProviderID: String?
    public var isMetadataOverridden: Bool

    public init(
        id: String,
        displayName: String? = nil,
        providerName: String? = nil,
        description: String? = nil,
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil,
        supportsTools: Bool = true,
        supportsReasoning: Bool = false,
        modalities: [String] = ["text"],
        isHidden: Bool = false,
        modelsDevProviderID: String? = nil,
        isMetadataOverridden: Bool = true
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.providerName = providerName
        self.description = description
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.supportsTools = supportsTools
        self.supportsReasoning = supportsReasoning
        self.modalities = modalities
        self.isHidden = isHidden
        self.modelsDevProviderID = modelsDevProviderID
        self.isMetadataOverridden = isMetadataOverridden
    }

    public func supportsInput(_ modality: String) -> Bool {
        modalities.contains(modality)
    }

    public mutating func setSupportsInput(_ modality: String, enabled: Bool) {
        if enabled {
            guard !modalities.contains(modality) else { return }
            modalities.append(modality)
        } else if modality != "text" {
            modalities.removeAll { $0 == modality }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case providerName
        case description
        case contextWindow
        case maxOutputTokens
        case supportsTools
        case supportsReasoning
        case modalities
        case isHidden
        case modelsDevProviderID
        case isMetadataOverridden
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        contextWindow = try container.decodeIfPresent(Int.self, forKey: .contextWindow)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        supportsTools = try container.decodeIfPresent(Bool.self, forKey: .supportsTools) ?? true
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning) ?? false
        modalities = try container.decodeIfPresent([String].self, forKey: .modalities) ?? ["text"]
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        modelsDevProviderID = try container.decodeIfPresent(
            String.self,
            forKey: .modelsDevProviderID
        )
        // Models saved before automatic discovery are user configuration and
        // must not be overwritten by a later refresh.
        isMetadataOverridden = try container.decodeIfPresent(
            Bool.self,
            forKey: .isMetadataOverridden
        ) ?? true
    }
}
