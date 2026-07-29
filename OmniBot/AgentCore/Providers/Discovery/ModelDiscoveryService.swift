import Foundation

nonisolated final class ModelDiscoveryService: ModelDiscovering, @unchecked Sendable {
    static let defaultCatalogURL: URL = {
        guard let url = URL(
            string: "https://omni.1775885.xyz/catalog/models-dev/api.json"
        ) else {
            fatalError("The models.dev catalog mirror URL literal is invalid.")
        }
        return url
    }()
    static let maximumProviderResponseBytes = 8 * 1_024 * 1_024
    static let maximumCatalogResponseBytes = 32 * 1_024 * 1_024

    private let providerTransport: OpenAIResponseTransport
    private let catalogTransport: OpenAIResponseTransport
    private let catalogURL: URL
    private let catalogCache = ModelsDevCatalogCache()
    private let catalogCacheLifetime: TimeInterval = 6 * 60 * 60

    init(
        session: URLSession = .shared,
        catalogURL: URL = defaultCatalogURL
    ) {
        providerTransport = OpenAIResponseTransport(
            session: session,
            maximumResponseBytes: Self.maximumProviderResponseBytes
        )
        catalogTransport = OpenAIResponseTransport(
            session: session,
            maximumResponseBytes: Self.maximumCatalogResponseBytes
        )
        self.catalogURL = catalogURL
    }

    func discoverModels(
        for profile: ProviderProfile,
        apiKey: String
    ) async throws -> ModelDiscoveryResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelDiscoveryError.missingAPIKey
        }

        async let descriptors = fetchProviderModels(profile: profile, apiKey: apiKey)
        async let catalogResult = fetchCatalogResult()

        let providerModels = try await descriptors
        guard !providerModels.isEmpty else {
            throw ModelDiscoveryError.emptyModelList
        }
        let catalog = await catalogResult
        try Task.checkCancellation()

        var seenIDs = Set<String>()
        let models = providerModels.compactMap { descriptor -> ModelOption? in
            let identifier = descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, seenIDs.insert(identifier).inserted else { return nil }
            let normalizedDescriptor = ProviderModelDescriptor(
                id: identifier,
                ownedBy: descriptor.ownedBy
            )
            return catalog.value?.modelOption(for: normalizedDescriptor, profile: profile)
                ?? ModelOption(
                    id: identifier,
                    providerName: descriptor.ownedBy,
                    isMetadataOverridden: false
                )
        }
        guard !models.isEmpty else {
            throw ModelDiscoveryError.emptyModelList
        }

        return ModelDiscoveryResult(
            models: models,
            notice: catalog.error.map {
                "模型列表已更新，但暂时无法从 models.dev 补全信息：\($0)"
            }
        )
    }

    static func modelsURL(for baseURL: URL) throws -> URL {
        do {
            return try ProviderEndpointResolver.url(for: baseURL, endpoint: .models)
        } catch {
            throw ModelDiscoveryError.invalidBaseURL
        }
    }

    private func fetchProviderModels(
        profile: ProviderProfile,
        apiKey: String
    ) async throws -> [ProviderModelDescriptor] {
        let url: URL
        do {
            url = try ProviderEndpointResolver.modelsURL(for: profile)
        } catch {
            throw ModelDiscoveryError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch profile.protocolType {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAICompatible, .deepSeek:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in profile.defaultHeaders
        where !ProviderStore.isSensitiveHeaderName(name) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await providerTransport.data(for: request)
        } catch let error as OpenAIResponseTransportError {
            if case .responseTooLarge(let maximumBytes) = error {
                throw ModelDiscoveryError.responseTooLarge(maximumBytes: maximumBytes)
            }
            throw ModelDiscoveryError.transport(error.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ModelDiscoveryError.transport(
                OpenAIResponseSecretRedactor.redact(error.localizedDescription, apiKey: apiKey)
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelDiscoveryError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let parsed = OpenAICompatibleClient.parseHTTPError(
                statusCode: httpResponse.statusCode,
                data: data,
                apiKey: apiKey
            )
            throw ModelDiscoveryError.httpError(
                statusCode: httpResponse.statusCode,
                message: parsed.localizedDescription
            )
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ProviderModelListResponse.self, from: data).data
        } catch {
            throw ModelDiscoveryError.invalidProviderResponse(
                OpenAIResponseSecretRedactor.redact(error.localizedDescription, apiKey: apiKey)
            )
        }
    }

    private func fetchCatalogResult() async -> ModelDiscoveryCatalogResult {
        do {
            return ModelDiscoveryCatalogResult(value: try await fetchCatalog(), error: nil)
        } catch is CancellationError {
            return ModelDiscoveryCatalogResult(value: nil, error: "请求已取消")
        } catch {
            return ModelDiscoveryCatalogResult(value: nil, error: error.localizedDescription)
        }
    }

    private func fetchCatalog() async throws -> ModelsDevCatalog {
        if let cached = await catalogCache.value(maximumAge: catalogCacheLifetime) {
            return cached
        }

        var request = URLRequest(url: catalogURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await catalogTransport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw ModelDiscoveryError.invalidHTTPResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let catalog = try decoder.decode(ModelsDevCatalog.self, from: data)
        await catalogCache.store(catalog)
        return catalog
    }

}
