import Foundation

extension OpenAICompatibleClient {
    public func stream(
        _ request: AgentChatRequest,
        apiKey: String,
        onSnapshot: @escaping @Sendable (AgentStreamSnapshot) async throws -> Void
    ) async throws -> AgentChatResponse {
        guard profile.protocolType != .anthropic,
              profile.wireAPI == .chatCompletions else {
            throw OpenAICompatibleClientError.unsupportedWireAPI(profile.wireAPI)
        }
        guard request.stream else {
            return try await complete(request, apiKey: apiKey)
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleClientError.emptyAPIKey
        }

        let accumulator = OpenAIStreamAccumulator(
            apiKey: apiKey,
            buffersLeadingInlineThinking: shouldBufferLeadingInlineThinking(for: request)
        )
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

                let chunk: OpenAIChatCompletionStreamChunk
                do {
                    chunk = try JSONDecoder().decode(
                        OpenAIChatCompletionStreamChunk.self,
                        from: Data(payload.utf8)
                    )
                } catch {
                    throw OpenAICompatibleClientError.responseDecodingFailed(
                        OpenAIResponseSecretRedactor.redact(
                            error.localizedDescription,
                            apiKey: apiKey
                        )
                    )
                }

                if let snapshot = try await accumulator.consume(chunk) {
                    try await onSnapshot(snapshot)
                }
            }
            guard response is HTTPURLResponse else {
                throw OpenAICompatibleClientError.invalidHTTPResponse
            }
            let result = try await accumulator.response()
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
                throw Self.parseHTTPError(statusCode: statusCode, data: data, apiKey: apiKey)
            }
        } catch let error as OpenAICompatibleClientError {
            throw error
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw OpenAICompatibleClientError.transport(
                OpenAIResponseSecretRedactor.redact(
                    error.localizedDescription,
                    apiKey: apiKey
                )
            )
        }
    }

    private func shouldBufferLeadingInlineThinking(for request: AgentChatRequest) -> Bool {
        guard profile.protocolType == .openAICompatible else { return false }
        let model = request.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isQwen = model.hasPrefix("qwen")
            || ["/qwen", ":qwen", "_qwen", "-qwen"].contains { model.contains($0) }
        if isQwen { return true }

        guard profile.baseURL.host?.lowercased() == "integrate.api.nvidia.com" else {
            return false
        }
        let lastComponent = model
            .split(whereSeparator: { $0 == "/" || $0 == ":" })
            .last
            .map(String.init) ?? model
        return lastComponent.replacingOccurrences(of: "_", with: "-") == "kimi-k2.6"
    }
}

private actor OpenAIStreamAccumulator {
    private struct ToolCallBuilder {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private let apiKey: String
    private let buffersLeadingInlineThinking: Bool
    private var rawContent = ""
    private var explicitReasoning = ""
    private var finishReason: String?
    private var usage = AgentUsage.zero
    private var toolCalls: [Int: ToolCallBuilder] = [:]
    private var lastEmittedSnapshot = AgentStreamSnapshot()
    private var didReceiveDone = false
    private var leadingInlineBuffer = ""
    private var leadingContentChunkCount = 0
    private var didResolveLeadingInlineBuffer: Bool

    init(apiKey: String, buffersLeadingInlineThinking: Bool) {
        self.apiKey = apiKey
        self.buffersLeadingInlineThinking = buffersLeadingInlineThinking
        didResolveLeadingInlineBuffer = !buffersLeadingInlineThinking
    }

    func consume(_ chunk: OpenAIChatCompletionStreamChunk) throws -> AgentStreamSnapshot? {
        if let wireUsage = chunk.usage {
            guard wireUsage.promptTokens >= 0,
                  wireUsage.completionTokens >= 0,
                  wireUsage.totalTokens.map({ $0 >= 0 }) ?? true,
                  wireUsage.promptTokensDetails?.cachedTokens.map({ $0 >= 0 }) ?? true else {
                throw OpenAICompatibleClientError.invalidUsage
            }
            usage = AgentUsage(
                promptTokens: wireUsage.promptTokens,
                completionTokens: wireUsage.completionTokens,
                totalTokens: wireUsage.totalTokens ?? AgentUsage.saturatingSum(
                    wireUsage.promptTokens,
                    wireUsage.completionTokens
                ),
                cachedTokens: wireUsage.promptTokensDetails?.cachedTokens ?? 0
            )
        }

        for choice in chunk.choices {
            if let value = choice.finishReason, !value.isEmpty { finishReason = value }
            observeReasoningSnapshot(ProviderReasoningText.first(
                in: choice.reasoningContent,
                choice.reasoning,
                choice.thinking
            ))
            if let delta = choice.delta {
                observeReasoningDelta(ProviderReasoningText.first(
                    in: delta.reasoningContent,
                    delta.reasoning,
                    delta.thinking
                ))
                if let value = delta.content { consumeContentDelta(value) }
                for toolCallDelta in delta.toolCalls ?? [] {
                    var builder = toolCalls[toolCallDelta.index] ?? ToolCallBuilder()
                    mergeStreamingField(&builder.id, toolCallDelta.id)
                    mergeStreamingField(&builder.name, toolCallDelta.function?.name)
                    if let arguments = toolCallDelta.function?.arguments {
                        mergeStreamingField(&builder.arguments, arguments)
                    }
                    toolCalls[toolCallDelta.index] = builder
                }
            }
            if let message = choice.message {
                observeReasoningSnapshot(ProviderReasoningText.first(
                    in: message.reasoningContent,
                    message.reasoning,
                    message.thinking
                ))
                consumeContentSnapshot(message.content)
                for (index, toolCall) in (message.toolCalls ?? []).enumerated() {
                    toolCalls[index] = ToolCallBuilder(
                        id: toolCall.id,
                        name: toolCall.function.name,
                        arguments: toolCall.function.arguments
                    )
                }
            }
        }
        if finishReason?.isEmpty == false { flushLeadingBufferAsContent() }

        let snapshot = safeSnapshot()
        guard !snapshot.isEmpty, snapshot != lastEmittedSnapshot else { return nil }
        lastEmittedSnapshot = snapshot
        return snapshot
    }

    func markDone() {
        didReceiveDone = true
        flushLeadingBufferAsContent()
    }

    private func safeSnapshot() -> AgentStreamSnapshot {
        let parsed = ProviderReasoningMarkupParser.parse(rawContent, isFinal: false)
        return AgentStreamSnapshot(
            content: OpenAIResponseSecretRedactor.redactStreamingSnapshot(
                parsed.content,
                apiKey: apiKey
            ),
            reasoningContent: OpenAIResponseSecretRedactor.redactStreamingSnapshot(
                explicitReasoning + parsed.reasoning,
                apiKey: apiKey
            )
        )
    }

    private func observeReasoningDelta(_ incoming: String?) {
        guard incoming?.isEmpty == false else { return }
        flushLeadingBufferAsContent()
        didResolveLeadingInlineBuffer = true
        mergeReasoning(incoming)
    }

    private func observeReasoningSnapshot(_ incoming: String?) {
        guard incoming?.isEmpty == false else { return }
        flushLeadingBufferAsContent()
        didResolveLeadingInlineBuffer = true
        mergeReasoningSnapshot(incoming)
    }

    private func mergeReasoning(_ incoming: String?) {
        guard let incoming, !incoming.isEmpty else { return }
        if incoming.hasPrefix(explicitReasoning) {
            explicitReasoning = incoming
        } else if !explicitReasoning.hasSuffix(incoming) {
            explicitReasoning += incoming
        }
    }

    private func mergeReasoningSnapshot(_ incoming: String?) {
        replaceWithSnapshot(&explicitReasoning, incoming)
    }

    private func consumeContentDelta(_ incoming: String) {
        guard !incoming.isEmpty else { return }
        guard buffersLeadingInlineThinking, !didResolveLeadingInlineBuffer else {
            rawContent += incoming
            return
        }
        leadingInlineBuffer += incoming
        leadingContentChunkCount += 1
        if resolveLeadingInlineThinkingIfClosed() { return }
        if leadingInlineBuffer.count >= 900 || leadingContentChunkCount >= 6 {
            flushLeadingBufferAsContent()
        }
    }

    private func consumeContentSnapshot(_ incoming: String?) {
        guard let incoming, !incoming.isEmpty else { return }
        guard buffersLeadingInlineThinking, !didResolveLeadingInlineBuffer else {
            replaceWithSnapshot(&rawContent, incoming)
            return
        }
        leadingInlineBuffer = incoming
        leadingContentChunkCount = max(leadingContentChunkCount, 1)
        if resolveLeadingInlineThinkingIfClosed() { return }
        if leadingInlineBuffer.count >= 900 {
            flushLeadingBufferAsContent()
        }
    }

    @discardableResult
    private func resolveLeadingInlineThinkingIfClosed() -> Bool {
        guard leadingInlineBuffer.range(
            of: "</think>",
            options: .caseInsensitive
        ) != nil else { return false }
        let parsed = ProviderReasoningMarkupParser.parse(leadingInlineBuffer)
        mergeReasoning(parsed.reasoning)
        rawContent += parsed.content
        leadingInlineBuffer = ""
        didResolveLeadingInlineBuffer = true
        return true
    }

    private func flushLeadingBufferAsContent() {
        guard !leadingInlineBuffer.isEmpty else { return }
        rawContent += leadingInlineBuffer
        leadingInlineBuffer = ""
        didResolveLeadingInlineBuffer = true
    }

    private func replaceWithSnapshot(_ target: inout String, _ incoming: String?) {
        guard let incoming, !incoming.isEmpty else { return }
        if incoming.hasPrefix(target) || !target.hasPrefix(incoming) {
            target = incoming
        }
    }

    private func mergeStreamingField(_ target: inout String, _ incoming: String?) {
        guard let incoming, !incoming.isEmpty, incoming != target else { return }
        if incoming.hasPrefix(target) {
            target = incoming
        } else {
            target += incoming
        }
    }

    func response() throws -> AgentChatResponse {
        guard didReceiveDone || finishReason?.isEmpty == false else {
            throw OpenAICompatibleClientError.transport(
                "Chat Completions stream ended before a normal termination signal."
            )
        }
        flushLeadingBufferAsContent()
        let calls = toolCalls.keys.sorted().compactMap { index -> AgentToolCall? in
            guard let builder = toolCalls[index] else { return nil }
            return AgentToolCall(
                id: builder.id,
                name: builder.name,
                arguments: builder.arguments
            )
        }
        guard !calls.contains(where: {
            OpenAIResponseSecretRedactor.containsCredentialVariant(in: $0.id, apiKey: apiKey)
                || OpenAIResponseSecretRedactor.containsCredentialVariant(
                    in: $0.name,
                    apiKey: apiKey
                )
                || OpenAIResponseSecretRedactor.containsCredentialVariantInJSON(
                    $0.arguments,
                    apiKey: apiKey
                )
        }) else {
            throw OpenAICompatibleClientError.credentialEchoInToolCall
        }

        let parsedContent = ProviderReasoningMarkupParser.parse(rawContent)
        let redactedContent = parsedContent.content.isEmpty
            ? nil
            : OpenAIResponseSecretRedactor.redact(parsedContent.content, apiKey: apiKey)
        let reasoning = explicitReasoning + parsedContent.reasoning
        let redactedReasoning = reasoning.isEmpty
            ? nil
            : OpenAIResponseSecretRedactor.redact(reasoning, apiKey: apiKey)
        guard redactedContent?.isEmpty == false
                || redactedReasoning?.isEmpty == false
                || !calls.isEmpty else {
            throw OpenAICompatibleClientError.emptyChoices
        }
        return AgentChatResponse(
            message: AgentMessage(
                role: .assistant,
                content: redactedContent,
                reasoningContent: redactedReasoning,
                toolCalls: calls
            ),
            usage: usage,
            finishReason: finishReason
        )
    }
}
