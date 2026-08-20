import Foundation

/// OpenAI-compatible `/chat/completions` client.
///
/// Requests are tracked by `AgentChatRequest.runID`, so cancellation propagates
/// into the underlying URLSession operation.
nonisolated public final class OpenAICompatibleClient: AgentChatStreaming, @unchecked Sendable {
    public let profile: ProviderProfile

    let responseTransport: OpenAIResponseTransport
    private let activeRequests = OpenAIActiveRequestStore()

    public init(profile: ProviderProfile, session: URLSession = .shared) {
        self.profile = profile
        responseTransport = OpenAIResponseTransport(session: session)
    }

    init(
        profile: ProviderProfile,
        session: URLSession,
        maximumResponseBytes: Int
    ) {
        self.profile = profile
        responseTransport = OpenAIResponseTransport(
            session: session,
            maximumResponseBytes: maximumResponseBytes
        )
    }

    public func complete(
        _ request: AgentChatRequest,
        apiKey: String
    ) async throws -> AgentChatResponse {
        guard profile.protocolType != .anthropic,
              profile.wireAPI == .chatCompletions else {
            throw OpenAICompatibleClientError.unsupportedWireAPI(profile.wireAPI)
        }
        guard !request.stream else {
            throw OpenAICompatibleClientError.streamingUnsupported
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleClientError.emptyAPIKey
        }

        let urlRequest = try makeURLRequest(request, apiKey: apiKey)
        let operation = Task {
            try Task.checkCancellation()
            return try await responseTransport.data(for: urlRequest)
        }
        let (data, response) = try await withTaskCancellationHandler {
            let registration = activeRequests.register(operation, for: request.runID)
            defer {
                activeRequests.remove(runID: request.runID, token: registration.token)
            }

            do {
                guard !registration.wasCancelledBeforeRegistration else {
                    throw CancellationError()
                }
                // Covers cancellation that happened after the operation was
                // created but before it was registered in activeRequests.
                try Task.checkCancellation()
                let result = try await operation.value
                try Task.checkCancellation()
                return result
            } catch {
                if Task.isCancelled || error is CancellationError {
                    throw CancellationError()
                }
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    throw CancellationError()
                }
                if let transportError = error as? OpenAIResponseTransportError,
                   case let .responseTooLarge(maximumBytes) = transportError {
                    throw OpenAICompatibleClientError.responseTooLarge(
                        maximumBytes: maximumBytes
                    )
                }
                throw OpenAICompatibleClientError.transport(
                    OpenAIResponseSecretRedactor.redact(
                        error.localizedDescription,
                        apiKey: apiKey
                    )
                )
            }
        } onCancel: {
            // Do not depend only on registration: cancellation can race with
            // the create/register window.
            operation.cancel()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleClientError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = Self.parseHTTPError(
                statusCode: httpResponse.statusCode,
                data: data,
                apiKey: apiKey
            )
            if request.promptCacheKey != nil, error.rejectsPromptCacheKey {
                return try await complete(
                    request.replacingPromptCacheKey(nil),
                    apiKey: apiKey
                )
            }
            throw error
        }

        let wireResponse: OpenAIChatCompletionResponseBody
        do {
            wireResponse = try JSONDecoder().decode(
                OpenAIChatCompletionResponseBody.self,
                from: data
            )
        } catch {
            if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data),
               envelope.error != nil || envelope.message != nil {
                throw Self.parseHTTPError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    apiKey: apiKey
                )
            }
            throw OpenAICompatibleClientError.responseDecodingFailed(
                Self.decodingMessage(error, data: data, apiKey: apiKey)
            )
        }

        guard let choice = wireResponse.choices.first else {
            throw OpenAICompatibleClientError.emptyChoices
        }

        let wireToolCalls = choice.message.toolCalls ?? []
        guard !wireToolCalls.contains(where: {
            OpenAIResponseSecretRedactor.containsCredentialVariant(
                in: $0.id,
                apiKey: apiKey
            )
                || OpenAIResponseSecretRedactor.containsCredentialVariant(
                    in: $0.function.name,
                    apiKey: apiKey
                )
                || OpenAIResponseSecretRedactor.containsCredentialVariantInJSON(
                    $0.function.arguments,
                    apiKey: apiKey
                )
        }) else {
            // Tool metadata is executable input. Replacing substrings could
            // silently change its JSON meaning, so reject the whole response.
            throw OpenAICompatibleClientError.credentialEchoInToolCall
        }
        let toolCalls = wireToolCalls.map {
            AgentToolCall(
                id: $0.id,
                name: $0.function.name,
                arguments: $0.function.arguments
            )
        }
        let usage: AgentUsage
        if let wireUsage = wireResponse.usage {
            guard wireUsage.promptTokens >= 0,
                  wireUsage.completionTokens >= 0,
                  wireUsage.promptTokensDetails?.cachedTokens.map({ $0 >= 0 }) ?? true,
                  wireUsage.promptTokensDetails?.cacheWriteTokens.map({ $0 >= 0 }) ?? true,
                  wireUsage.totalTokens.map({ $0 >= 0 }) ?? true else {
                throw OpenAICompatibleClientError.invalidUsage
            }
            let cachedTokens = wireUsage.promptTokensDetails?.cachedTokens ?? 0
            let cacheCreationTokens = wireUsage.promptTokensDetails?.cacheWriteTokens ?? 0
            guard cachedTokens <= wireUsage.promptTokens,
                  cacheCreationTokens <= wireUsage.promptTokens - cachedTokens else {
                throw OpenAICompatibleClientError.invalidUsage
            }
            usage = AgentUsage(
                promptTokens: wireUsage.promptTokens - cachedTokens,
                completionTokens: wireUsage.completionTokens,
                totalTokens: wireUsage.totalTokens ?? AgentUsage.saturatingSum(
                    wireUsage.promptTokens,
                    wireUsage.completionTokens
                ),
                cachedTokens: cachedTokens,
                cacheCreationTokens: cacheCreationTokens,
                reportsCacheUsage: wireUsage.promptTokensDetails?.cachedTokens != nil
                    || wireUsage.promptTokensDetails?.cacheWriteTokens != nil
            )
        } else {
            usage = .zero
        }

        let rawReasoning = ProviderReasoningText.first(
            in: choice.message.reasoningContent,
            choice.message.reasoning,
            choice.message.thinking,
            choice.reasoningContent,
            choice.reasoning,
            choice.thinking
        ) ?? ""
        let parsedContent = ProviderReasoningMarkupParser.parse(choice.message.content ?? "")
        let reasoning = rawReasoning + parsedContent.reasoning

        return AgentChatResponse(
            message: AgentMessage(
                role: .assistant,
                content: parsedContent.content.isEmpty
                    ? nil
                    : OpenAIResponseSecretRedactor.redact(parsedContent.content, apiKey: apiKey),
                reasoningContent: reasoning.isEmpty
                    ? nil
                    : OpenAIResponseSecretRedactor.redact(reasoning, apiKey: apiKey),
                toolCalls: toolCalls
            ),
            usage: usage,
            finishReason: choice.finishReason
        )
    }

    public func cancel(runID: UUID) async {
        activeRequests.cancel(runID: runID)
    }

    public nonisolated static func chatCompletionsURL(for baseURL: URL) throws -> URL {
        try ProviderEndpointResolver.url(for: baseURL, endpoint: .chatCompletions)
    }

    public nonisolated static func parseHTTPError(
        statusCode: Int,
        data: Data,
        apiKey: String = ""
    ) -> OpenAICompatibleClientError {
        let decoder = JSONDecoder()
        let envelope = try? decoder.decode(OpenAIErrorEnvelope.self, from: data)
        let rawBody = Self.bodyPreview(data)
        let rawMessage = envelope?.error?.message
            ?? envelope?.message
            ?? rawBody
            ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let redact: (String) -> String = {
            OpenAIResponseSecretRedactor.redact($0, apiKey: apiKey)
        }

        return .httpError(
            statusCode: statusCode,
            message: redact(rawMessage),
            type: envelope?.error?.type.map(redact),
            code: (envelope?.error?.code?.value).map(redact),
            body: rawBody.map(redact)
        )
    }

    func makeURLRequest(
        _ request: AgentChatRequest,
        apiKey: String
    ) throws -> URLRequest {
        let url = try ProviderEndpointResolver.url(
            for: profile.baseURL,
            endpoint: .chatCompletions
        )
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
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            urlRequest.httpBody = try encoder.encode(
                OpenAIChatCompletionRequestBody(
                    request,
                    protocolType: profile.protocolType
                )
            )
        } catch {
            throw OpenAICompatibleClientError.requestEncodingFailed(
                OpenAIResponseSecretRedactor.redact(
                    error.localizedDescription,
                    apiKey: apiKey
                )
            )
        }
        return urlRequest
    }

    nonisolated static func decodingMessage(
        _ error: Error,
        data: Data,
        apiKey: String
    ) -> String {
        let message: String
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case let .dataCorrupted(context):
                message = context.debugDescription
            case let .keyNotFound(key, context):
                message = "Missing '\(key.stringValue)' at \(codingPath(context.codingPath))."
            case let .typeMismatch(_, context):
                message = "Type mismatch at \(codingPath(context.codingPath)): \(context.debugDescription)"
            case let .valueNotFound(_, context):
                message = "Missing value at \(codingPath(context.codingPath)): \(context.debugDescription)"
            @unknown default:
                message = error.localizedDescription
            }
        } else if let body = bodyPreview(data) {
            message = "\(error.localizedDescription). Body: \(body)"
        } else {
            message = error.localizedDescription
        }
        return OpenAIResponseSecretRedactor.redact(message, apiKey: apiKey)
    }

    private nonisolated static func codingPath(_ codingPath: [CodingKey]) -> String {
        let value = codingPath.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "<root>" : value
    }

    private nonisolated static func bodyPreview(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let prefix = data.prefix(4_096)
        return String(data: prefix, encoding: .utf8)
    }
}

nonisolated private final class OpenAIActiveRequestStore: @unchecked Sendable {
    private struct Entry {
        let token: UUID
        let task: Task<(Data, URLResponse), Error>
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var pendingCancellations: Set<UUID> = []
    private let maximumPendingCancellationCount = 1_024

    func register(
        _ task: Task<(Data, URLResponse), Error>,
        for runID: UUID
    ) -> (token: UUID, wasCancelledBeforeRegistration: Bool) {
        let token = UUID()
        lock.lock()
        let wasCancelledBeforeRegistration = pendingCancellations.remove(runID) != nil
        let previous = wasCancelledBeforeRegistration
            ? nil
            : entries.updateValue(Entry(token: token, task: task), forKey: runID)
        lock.unlock()
        if wasCancelledBeforeRegistration {
            task.cancel()
        }
        previous?.task.cancel()
        return (token, wasCancelledBeforeRegistration)
    }

    func remove(runID: UUID, token: UUID) {
        lock.lock()
        if entries[runID]?.token == token {
            entries.removeValue(forKey: runID)
        }
        lock.unlock()
    }

    func cancel(runID: UUID) {
        lock.lock()
        let task = entries.removeValue(forKey: runID)?.task
        if task == nil {
            if pendingCancellations.count >= maximumPendingCancellationCount,
               let pendingRun = pendingCancellations.first {
                pendingCancellations.remove(pendingRun)
            }
            pendingCancellations.insert(runID)
        }
        lock.unlock()
        task?.cancel()
    }
}
