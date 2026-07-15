import Foundation

nonisolated final class OpenAIResponsesClient: AgentChatStreaming, @unchecked Sendable {
    let profile: ProviderProfile
    private let responseTransport: OpenAIResponseTransport

    init(
        profile: ProviderProfile,
        session: URLSession = .shared,
        maximumResponseBytes: Int = OpenAIResponseTransport.defaultMaximumResponseBytes
    ) {
        self.profile = profile
        responseTransport = OpenAIResponseTransport(
            session: session,
            maximumResponseBytes: maximumResponseBytes
        )
    }

    func complete(
        _ request: AgentChatRequest,
        apiKey: String
    ) async throws -> AgentChatResponse {
        guard !request.stream else {
            throw OpenAICompatibleClientError.streamingUnsupported
        }
        try validate(apiKey: apiKey)
        let urlRequest = try makeURLRequest(request, apiKey: apiKey)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await responseTransport.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenAIResponseTransportError {
            if case let .responseTooLarge(maximumBytes) = error {
                throw OpenAICompatibleClientError.responseTooLarge(maximumBytes: maximumBytes)
            }
            throw OpenAICompatibleClientError.transport(error.localizedDescription)
        } catch {
            throw OpenAICompatibleClientError.transport(
                OpenAIResponseSecretRedactor.redact(error.localizedDescription, apiKey: apiKey)
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAICompatibleClient.parseHTTPError(
                statusCode: httpResponse.statusCode,
                data: data,
                apiKey: apiKey
            )
        }

        let value: AgentValue
        do {
            value = try JSONDecoder().decode(AgentValue.self, from: data)
        } catch {
            throw OpenAICompatibleClientError.responseDecodingFailed(
                OpenAICompatibleClient.decodingMessage(error, data: data, apiKey: apiKey)
            )
        }
        let accumulator = OpenAIResponsesAccumulator(apiKey: apiKey)
        _ = try await accumulator.consume(value)
        return try await accumulator.response()
    }

    func stream(
        _ request: AgentChatRequest,
        apiKey: String,
        onSnapshot: @escaping @Sendable (AgentStreamSnapshot) async throws -> Void
    ) async throws -> AgentChatResponse {
        guard request.stream else {
            return try await complete(request, apiKey: apiKey)
        }
        try validate(apiKey: apiKey)
        let accumulator = OpenAIResponsesAccumulator(apiKey: apiKey)
        let urlRequest = try makeURLRequest(request, apiKey: apiKey)

        do {
            let response = try await responseTransport.lines(for: urlRequest) { line in
                guard line.hasPrefix("data:") else { return }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard !payload.isEmpty else { return }
                if payload == "[DONE]" {
                    await accumulator.markDone()
                    return
                }
                let event: AgentValue
                do {
                    event = try JSONDecoder().decode(AgentValue.self, from: Data(payload.utf8))
                } catch {
                    throw OpenAICompatibleClientError.responseDecodingFailed(
                        OpenAIResponseSecretRedactor.redact(
                            error.localizedDescription,
                            apiKey: apiKey
                        )
                    )
                }
                if let snapshot = try await accumulator.consume(event) {
                    try await onSnapshot(snapshot)
                }
            }
            guard response is HTTPURLResponse else {
                throw OpenAICompatibleClientError.invalidHTTPResponse
            }
            let result = try await accumulator.response(requireNormalTermination: true)
            let finalSnapshot = AgentStreamSnapshot(
                content: result.message.content ?? "",
                reasoningContent: result.message.reasoningContent ?? ""
            )
            if !finalSnapshot.isEmpty {
                try await onSnapshot(finalSnapshot)
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenAIResponseTransportError {
            switch error {
            case let .responseTooLarge(maximumBytes):
                throw OpenAICompatibleClientError.responseTooLarge(maximumBytes: maximumBytes)
            case let .httpError(statusCode, data):
                throw OpenAICompatibleClient.parseHTTPError(
                    statusCode: statusCode,
                    data: data,
                    apiKey: apiKey
                )
            }
        } catch let error as OpenAICompatibleClientError {
            throw error
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw OpenAICompatibleClientError.transport(
                OpenAIResponseSecretRedactor.redact(error.localizedDescription, apiKey: apiKey)
            )
        }
    }

    private func validate(apiKey: String) throws {
        guard profile.protocolType == .openAICompatible,
              profile.wireAPI == .responses else {
            throw OpenAICompatibleClientError.unsupportedWireAPI(profile.wireAPI)
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleClientError.emptyAPIKey
        }
    }

    private func makeURLRequest(
        _ request: AgentChatRequest,
        apiKey: String
    ) throws -> URLRequest {
        let url = try ProviderEndpointResolver.url(for: profile.baseURL, endpoint: .responses)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (name, value) in profile.defaultHeaders
        where !ProviderStore.isSensitiveHeaderName(name) {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            urlRequest.httpBody = try encoder.encode(OpenAIResponsesRequestBody(request))
        } catch {
            throw OpenAICompatibleClientError.requestEncodingFailed(
                OpenAIResponseSecretRedactor.redact(error.localizedDescription, apiKey: apiKey)
            )
        }
        return urlRequest
    }
}
