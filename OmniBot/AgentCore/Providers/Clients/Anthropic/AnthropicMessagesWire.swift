import Foundation

nonisolated struct AnthropicMessagesRequestBody: Encodable, Sendable {
    let value: AgentValue

    init(_ request: AgentChatRequest) {
        let enablesPromptCaching = request.promptCacheKey != nil
        let effectiveEffort = Self.anthropicEffort(request.reasoningEffort)
        let requestedMaxTokens = request.maxTokens
            ?? (effectiveEffort == nil ? 4_096 : 16_000)
        let usesManualThinking = effectiveEffort != nil
            && Self.requiresManualThinking(model: request.model)
        let maxTokens = usesManualThinking ? max(requestedMaxTokens, 1_025) : requestedMaxTokens
        var payload: [String: AgentValue] = [
            "model": .string(request.model),
            "max_tokens": .number(Double(maxTokens)),
            "messages": .array(Self.messages(
                from: request.messages,
                enablesPromptCaching: enablesPromptCaching
            )),
            "stream": .bool(request.stream),
        ]

        let system = request.messages
            .filter { $0.role == .system }
            .compactMap(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !system.isEmpty {
            if enablesPromptCaching {
                payload["system"] = .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(system),
                        "cache_control": Self.ephemeralCacheControl,
                    ]),
                ])
            } else {
                payload["system"] = .string(system)
            }
        }
        if let temperature = request.temperature, effectiveEffort == nil {
            payload["temperature"] = .number(temperature)
        }
        if !request.tools.isEmpty {
            payload["tools"] = .array(request.tools.enumerated().map { index, definition in
                var tool: [String: AgentValue] = [
                    "name": .string(definition.name),
                    "description": .string(definition.description),
                    "input_schema": definition.parameters,
                ]
                if enablesPromptCaching, index == request.tools.count - 1 {
                    tool["cache_control"] = Self.ephemeralCacheControl
                }
                return .object(tool)
            })
        }
        if let effort = effectiveEffort {
            if usesManualThinking {
                payload["thinking"] = .object([
                    "type": .string("enabled"),
                    "budget_tokens": .number(Double(min(4_096, maxTokens - 1))),
                ])
            } else {
                payload["thinking"] = .object([
                    "type": .string("adaptive"),
                    "display": .string("summarized"),
                ])
                payload["output_config"] = .object([
                    "effort": .string(effort.rawValue),
                ])
            }
        }
        value = .object(payload)
    }

    private static let ephemeralCacheControl = AgentValue.object([
        "type": .string("ephemeral"),
    ])

    private static func anthropicEffort(
        _ effort: AgentReasoningEffort?
    ) -> AgentReasoningEffort? {
        switch effort {
        case .xhigh, .max:
            .high
        case .low, .medium, .high:
            effort
        case .no, nil:
            nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }

    private static func messages(
        from messages: [AgentMessage],
        enablesPromptCaching: Bool
    ) -> [AgentValue] {
        struct PendingMessage {
            var role: String
            var content: [AgentValue]
            var isToolResultBatch: Bool
        }

        var pending: [PendingMessage] = []
        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                guard let content = message.content, !content.isEmpty else { continue }
                pending.append(PendingMessage(
                    role: "user",
                    content: [textBlock(content)],
                    isToolResultBatch: false
                ))
            case .assistant:
                if let exactContent = message.providerMetadata?
                    .objectValue?["anthropic_content"]?.arrayValue,
                   !exactContent.isEmpty {
                    pending.append(PendingMessage(
                        role: "assistant",
                        content: exactContent,
                        isToolResultBatch: false
                    ))
                    continue
                }
                var content: [AgentValue] = []
                if let text = message.content, !text.isEmpty {
                    content.append(textBlock(text))
                }
                content.append(contentsOf: message.toolCalls.map { call in
                    .object([
                        "type": .string("tool_use"),
                        "id": .string(call.id),
                        "name": .string(call.name),
                        "input": toolInput(from: call.arguments),
                    ])
                })
                guard !content.isEmpty else { continue }
                pending.append(PendingMessage(
                    role: "assistant",
                    content: content,
                    isToolResultBatch: false
                ))
            case .tool:
                guard let callID = message.toolCallID else { continue }
                let block = AgentValue.object([
                    "type": .string("tool_result"),
                    "tool_use_id": .string(callID),
                    "content": .string(message.content ?? ""),
                ])
                if pending.last?.role == "user", pending.last?.isToolResultBatch == true {
                    pending[pending.count - 1].content.append(block)
                } else {
                    pending.append(PendingMessage(
                        role: "user",
                        content: [block],
                        isToolResultBatch: true
                    ))
                }
            case .system:
                break
            }
        }

        if enablesPromptCaching,
           let messageIndex = pending.indices.last,
           let blockIndex = pending[messageIndex].content.indices.last {
            pending[messageIndex].content[blockIndex] = addingCacheControl(
                to: pending[messageIndex].content[blockIndex]
            )
        }

        return pending.map { message in
            .object([
                "role": .string(message.role),
                "content": .array(message.content),
            ])
        }
    }

    private static func addingCacheControl(to value: AgentValue) -> AgentValue {
        guard var object = value.objectValue else { return value }
        switch object["type"]?.stringValue {
        case "text", "tool_result", "tool_use":
            object["cache_control"] = ephemeralCacheControl
            return .object(object)
        default:
            return value
        }
    }

    private static func textBlock(_ text: String) -> AgentValue {
        .object([
            "type": .string("text"),
            "text": .string(text),
        ])
    }

    private static func toolInput(from arguments: String) -> AgentValue {
        guard let data = arguments.data(using: .utf8),
              let value = try? JSONDecoder().decode(AgentValue.self, from: data) else {
            return .object(["raw": .string(arguments)])
        }
        if value.objectValue != nil { return value }
        return .object(["value": value])
    }

    static func requiresManualThinking(model: String) -> Bool {
        let model = model.lowercased()
        return ["3-7", "3.7", "4-0", "4-1", "4-5", "4.5", "haiku-4-5"]
            .contains { model.contains($0) }
    }

    static func supportsInterleavedThinking(model: String) -> Bool {
        let model = model.lowercased()
        return !["haiku-4-5", "haiku-4.5"].contains { model.contains($0) }
    }
}

actor AnthropicMessagesAccumulator {
    private struct ContentBlockBuilder: Sendable {
        var type = ""
        var id = ""
        var name = ""
        var text = ""
        var thinking = ""
        var signature = ""
        var redactedData: AgentValue?
        var arguments = ""
        var input: AgentValue?
    }

    private let apiKey: String
    private var blocks: [Int: ContentBlockBuilder] = [:]
    private var finishReason: String?
    private var inputTokens = 0
    private var outputTokens = 0
    private var cachedTokens = 0
    private var cacheCreationTokens = 0
    private var reportsCacheUsage = false
    private var lastEmittedSnapshot = AgentStreamSnapshot()
    private var didReceiveMessageStop = false

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func consume(_ event: AgentValue) throws -> AgentStreamSnapshot? {
        guard let object = event.objectValue else { return nil }
        switch object["type"]?.stringValue {
        case "message_start":
            if let message = object["message"] {
                try consumeMessage(message)
            }
        case "content_block_start":
            let index = Self.integer(object["index"]) ?? blocks.count
            if let block = object["content_block"] {
                blocks[index] = builder(from: block)
            }
        case "content_block_delta":
            let index = Self.integer(object["index"]) ?? 0
            guard let delta = object["delta"]?.objectValue else { break }
            var block = blocks[index] ?? ContentBlockBuilder()
            switch delta["type"]?.stringValue {
            case "text_delta":
                block.type = block.type.isEmpty ? "text" : block.type
                block.text += delta["text"]?.stringValue ?? ""
            case "thinking_delta":
                block.type = block.type.isEmpty ? "thinking" : block.type
                block.thinking += delta["thinking"]?.stringValue ?? ""
            case "signature_delta":
                block.signature += delta["signature"]?.stringValue ?? ""
            case "input_json_delta":
                block.type = block.type.isEmpty ? "tool_use" : block.type
                block.arguments += delta["partial_json"]?.stringValue ?? ""
            default:
                break
            }
            blocks[index] = block
        case "message_delta":
            if let delta = object["delta"]?.objectValue,
               let stopReason = delta["stop_reason"]?.stringValue {
                finishReason = Self.normalizedFinishReason(stopReason)
            }
            try consumeUsage(object["usage"])
        case "message_stop":
            didReceiveMessageStop = true
        case "ping", "content_block_stop":
            break
        case "error":
            let message = object["error"]?.objectValue?["message"]?.stringValue
                ?? "Anthropic stream failed."
            throw OpenAICompatibleClientError.transport(
                OpenAIResponseSecretRedactor.redact(message, apiKey: apiKey)
            )
        default:
            if object["content"] != nil {
                try consumeMessage(event)
            }
        }

        let snapshot = safeSnapshot()
        guard !snapshot.isEmpty, snapshot != lastEmittedSnapshot else { return nil }
        lastEmittedSnapshot = snapshot
        return snapshot
    }

    func response(requireMessageStop: Bool = false) throws -> AgentChatResponse {
        guard !requireMessageStop || didReceiveMessageStop else {
            throw OpenAICompatibleClientError.transport(
                "Anthropic Messages stream ended before message_stop."
            )
        }
        var calls: [AgentToolCall] = []
        for index in blocks.keys.sorted() {
            guard let block = blocks[index], block.type == "tool_use" else { continue }
            calls.append(AgentToolCall(
                id: block.id,
                name: block.name,
                arguments: try serializedInput(for: block)
            ))
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

        let snapshot = safeSnapshot(isFinal: true)
        guard !snapshot.isEmpty || !calls.isEmpty else {
            throw OpenAICompatibleClientError.emptyChoices
        }
        let noncachedInputTokens = AgentUsage.saturatingSum(
            inputTokens,
            cacheCreationTokens
        )
        let totalInputTokens = AgentUsage.saturatingSum(
            noncachedInputTokens,
            cachedTokens
        )
        let usage = AgentUsage(
            promptTokens: noncachedInputTokens,
            completionTokens: outputTokens,
            totalTokens: AgentUsage.saturatingSum(totalInputTokens, outputTokens),
            cachedTokens: cachedTokens,
            cacheCreationTokens: cacheCreationTokens,
            reportsCacheUsage: reportsCacheUsage
        )
        return AgentChatResponse(
            message: AgentMessage(
                role: .assistant,
                content: snapshot.content.isEmpty ? nil : snapshot.content,
                reasoningContent: snapshot.reasoningContent.isEmpty
                    ? nil
                    : snapshot.reasoningContent,
                providerMetadata: try safeProviderMetadata(),
                toolCalls: calls
            ),
            usage: usage,
            finishReason: calls.isEmpty ? finishReason : "tool_calls"
        )
    }

    private func consumeMessage(_ value: AgentValue) throws {
        guard let object = value.objectValue else { return }
        if let content = object["content"]?.arrayValue {
            for (index, block) in content.enumerated() {
                blocks[index] = builder(from: block)
            }
        }
        if let stopReason = object["stop_reason"]?.stringValue {
            finishReason = Self.normalizedFinishReason(stopReason)
        }
        try consumeUsage(object["usage"])
    }

    private func consumeUsage(_ value: AgentValue?) throws {
        guard let usage = value?.objectValue else { return }
        let nextInputTokens = Self.integer(usage["input_tokens"]) ?? inputTokens
        let nextOutputTokens = Self.integer(usage["output_tokens"]) ?? outputTokens
        let nextCachedTokens = Self.integer(usage["cache_read_input_tokens"])
            ?? cachedTokens
        let nextCacheCreationTokens = Self.integer(usage["cache_creation_input_tokens"])
            ?? cacheCreationTokens
        guard nextInputTokens >= 0,
              nextOutputTokens >= 0,
              nextCachedTokens >= 0,
              nextCacheCreationTokens >= 0 else {
            throw OpenAICompatibleClientError.invalidUsage
        }
        inputTokens = nextInputTokens
        outputTokens = nextOutputTokens
        cachedTokens = nextCachedTokens
        cacheCreationTokens = nextCacheCreationTokens
        reportsCacheUsage = reportsCacheUsage
            || usage["cache_read_input_tokens"] != nil
            || usage["cache_creation_input_tokens"] != nil
    }

    private func builder(from value: AgentValue) -> ContentBlockBuilder {
        guard let object = value.objectValue else { return ContentBlockBuilder() }
        var builder = ContentBlockBuilder()
        builder.type = object["type"]?.stringValue ?? ""
        builder.id = object["id"]?.stringValue ?? ""
        builder.name = object["name"]?.stringValue ?? ""
        builder.text = object["text"]?.stringValue ?? ""
        builder.thinking = object["thinking"]?.stringValue ?? ""
        builder.signature = object["signature"]?.stringValue ?? ""
        builder.redactedData = object["data"]
        builder.input = object["input"]
        return builder
    }

    private func blockValue(_ block: ContentBlockBuilder) throws -> AgentValue {
        var value: [String: AgentValue] = ["type": .string(block.type)]
        switch block.type {
        case "text":
            value["text"] = .string(block.text)
        case "thinking":
            value["thinking"] = .string(block.thinking)
            if !block.signature.isEmpty { value["signature"] = .string(block.signature) }
        case "redacted_thinking":
            if let data = block.redactedData { value["data"] = data }
        case "tool_use":
            value["id"] = .string(block.id)
            value["name"] = .string(block.name)
            value["input"] = try parsedInput(for: block)
        default:
            break
        }
        return .object(value)
    }

    private func safeSnapshot(isFinal: Bool = false) -> AgentStreamSnapshot {
        let content = blocks.keys.sorted().compactMap { index -> String? in
            guard let block = blocks[index], block.type == "text" else { return nil }
            return block.text
        }.joined()
        let reasoning = blocks.keys.sorted().compactMap { index -> String? in
            guard let block = blocks[index], block.type == "thinking" else { return nil }
            return block.thinking
        }.joined()
        let redact: (String) -> String = { value in
            if isFinal {
                OpenAIResponseSecretRedactor.redact(value, apiKey: self.apiKey)
            } else {
                OpenAIResponseSecretRedactor.redactStreamingSnapshot(
                    value,
                    apiKey: self.apiKey
                )
            }
        }
        return AgentStreamSnapshot(content: redact(content), reasoningContent: redact(reasoning))
    }

    private func safeProviderMetadata() throws -> AgentValue? {
        var content: [AgentValue] = []
        for index in blocks.keys.sorted() {
            guard let block = blocks[index] else { continue }
            content.append(try blockValue(block))
        }
        let metadata = AgentValue.object([
            "anthropic_content": .array(content),
        ])
        guard let data = try? JSONEncoder().encode(metadata),
              let text = String(data: data, encoding: .utf8),
              !OpenAIResponseSecretRedactor.containsCredentialVariant(
                  in: text,
                  apiKey: apiKey
              ) else {
            return nil
        }
        return metadata
    }

    private func serializedInput(for block: ContentBlockBuilder) throws -> String {
        let value = try parsedInput(for: block)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            guard let text = String(data: data, encoding: .utf8) else {
                throw OpenAICompatibleClientError.responseDecodingFailed(
                    "Anthropic tool input could not be represented as UTF-8 JSON."
                )
            }
            return text
        } catch let error as OpenAICompatibleClientError {
            throw error
        } catch {
            throw OpenAICompatibleClientError.responseDecodingFailed(
                OpenAIResponseSecretRedactor.redact(
                    error.localizedDescription,
                    apiKey: apiKey
                )
            )
        }
    }

    private func parsedInput(for block: ContentBlockBuilder) throws -> AgentValue {
        if !block.arguments.isEmpty {
            guard let data = block.arguments.data(using: .utf8) else {
                throw OpenAICompatibleClientError.responseDecodingFailed(
                    "Anthropic streamed tool input was not valid UTF-8."
                )
            }
            let value: AgentValue
            do {
                value = try JSONDecoder().decode(AgentValue.self, from: data)
            } catch {
                throw OpenAICompatibleClientError.responseDecodingFailed(
                    OpenAIResponseSecretRedactor.redact(
                        "Anthropic streamed tool input was incomplete or invalid JSON: "
                            + error.localizedDescription,
                        apiKey: apiKey
                    )
                )
            }
            return value.objectValue == nil ? .object(["value": value]) : value
        }
        return block.input ?? .object([:])
    }

    private static func integer(_ value: AgentValue?) -> Int? {
        guard let number = value?.numberValue,
              number.isFinite,
              number >= Double(Int.min),
              number <= Double(Int.max) else { return nil }
        return Int(number)
    }

    private static func normalizedFinishReason(_ value: String) -> String {
        switch value {
        case "max_tokens", "model_context_window_exceeded":
            "length"
        case "tool_use":
            "tool_calls"
        default:
            value
        }
    }
}
