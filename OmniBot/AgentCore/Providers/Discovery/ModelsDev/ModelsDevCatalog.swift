import Foundation

nonisolated struct ModelsDevCatalog: Decodable, Equatable, Sendable {
    let providers: [String: ModelsDevProvider]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        providers = try container.decode([String: ModelsDevProvider].self)
    }

    func modelOption(
        for descriptor: ProviderModelDescriptor,
        profile: ProviderProfile
    ) -> ModelOption? {
        let candidates = providers.values.compactMap { provider -> ModelsDevCandidate? in
            guard let model = provider.models[descriptor.id] else { return nil }
            return ModelsDevCandidate(
                provider: provider,
                model: model,
                score: score(
                    provider: provider,
                    descriptor: descriptor,
                    profile: profile
                )
            )
        }
        guard let match = candidates.sorted(by: ModelsDevCandidate.precedes).first else {
            return nil
        }

        return ModelOption(
            id: descriptor.id,
            displayName: match.model.name,
            providerName: match.provider.name,
            description: match.model.description,
            contextWindow: match.model.limit?.context,
            maxOutputTokens: match.model.limit?.output,
            supportsTools: match.model.toolCall,
            supportsReasoning: match.model.reasoning,
            modalities: match.model.modalities?.input ?? ["text"],
            modelsDevProviderID: match.provider.id,
            isMetadataOverridden: false
        )
    }

    private func score(
        provider: ModelsDevProvider,
        descriptor: ProviderModelDescriptor,
        profile: ProviderProfile
    ) -> Int {
        var score = 0
        let providerID = Self.normalized(provider.id)
        let providerName = Self.normalized(provider.name)
        let profileName = Self.normalized(profile.name)
        let host = Self.normalized(profile.baseURL.host ?? "")
        let providerAPIURL = provider.api.flatMap { URL(string: $0) }

        if let api = providerAPIURL,
            Self.normalizedEndpoint(api) == Self.normalizedEndpoint(profile.baseURL)
        {
            score += 1_000
        } else if let apiHost = providerAPIURL?.host,
            apiHost.caseInsensitiveCompare(profile.baseURL.host ?? "") == .orderedSame
        {
            score += 900
        }
        if profileName == providerID || profileName == providerName {
            score += 800
        }
        if !providerID.isEmpty, host.contains(providerID) {
            score += 700
        }
        if descriptor.id.split(separator: "/").first.map(String.init) == provider.id {
            score += 600
        }
        if let ownedBy = descriptor.ownedBy,
            Self.normalized(ownedBy) == providerID
                || Self.normalized(ownedBy) == providerName
        {
            score += 500
        }
        if provider.id == modelLabPrefix(for: descriptor.id) {
            score += 400
        }
        return score
    }

    private func modelLabPrefix(for modelID: String) -> String? {
        guard let separator = modelID.firstIndex(of: "/") else { return nil }
        return String(modelID[..<separator])
    }

    private static func normalized(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func normalizedEndpoint(_ url: URL) -> String {
        url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}
