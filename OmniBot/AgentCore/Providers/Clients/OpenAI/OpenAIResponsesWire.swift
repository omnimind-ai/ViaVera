import Foundation

nonisolated struct OpenAIResponsesRequestBody: Encodable, Sendable {
    let value: AgentValue

    init(_ request: AgentChatRequest) {
        var payload: [String: AgentValue] = [
            "model": .string(request.model),
            "input": .array(Self.inputItems(for: request.messages)),
            "stream": .bool(request.stream),
        ]
        let instructions = request.messages
            .filter { $0.role == .system }
            .compactMap(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !instructions.isEmpty {
            payload["instructions"] = .string(instructions)
        }
        if let maxTokens = request.maxTokens {
            payload["max_output_tokens"] = .number(Double(maxTokens))
        }
        if !request.tools.isEmpty {
            payload["tools"] = .array(request.tools.map { definition in
                var tool: [String: AgentValue] = [
                    "type": .string("function"),
                    "name": .string(definition.name),
                    "parameters": definition.parameters,
                ]
                if !definition.description.isEmpty {
                    tool["description"] = .string(definition.description)
                }
                return .object(tool)
            })
        }
        if let reasoningEffort = Self.responsesEffort(request.reasoningEffort) {
            payload["reasoning"] = .object([
                "effort": .string(reasoningEffort.rawValue),
                "summary": .string("auto"),
            ])
        }
        value = .object(payload)
    }

    private static func responsesEffort(
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

    private static func inputItems(for messages: [AgentMessage]) -> [AgentValue] {
        var items: [AgentValue] = []
        for message in messages where message.role != .system {
            switch message.role {
            case .tool:
                guard let callID = message.toolCallID else { continue }
                items.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(callID),
                    "output": .string(message.content ?? ""),
                ]))
            case .assistant:
                if let responseItems = message.providerMetadata?
                    .objectValue?["openai_response_items"]?.arrayValue {
                    items.append(contentsOf: responseItems)
                }
                if let content = message.content, !content.isEmpty {
                    items.append(messageItem(role: "assistant", text: content))
                }
                items.append(contentsOf: message.toolCalls.map { call in
                    .object([
                        "type": .string("function_call"),
                        "call_id": .string(call.id),
                        "name": .string(call.name),
                        "arguments": .string(call.arguments),
                    ])
                })
            case .user:
                if let content = message.content, !content.isEmpty {
                    items.append(messageItem(role: "user", text: content))
                }
            case .system:
                break
            }
        }
        return items
    }

    private static func messageItem(role: String, text: String) -> AgentValue {
        .object([
            "role": .string(role),
            "content": .array([
                .object([
                    "type": .string("input_text"),
                    "text": .string(text),
                ]),
            ]),
        ])
    }
}

actor OpenAIResponsesAccumulator {
    private struct ToolCallBuilder: Sendable {
        var order: Int
        var itemID = ""
        var callID = ""
        var name = ""
        var arguments = ""
    }

    private let apiKey: String
    private var content = ""
    private var reasoning = ""
    private var finishReason: String?
    private var usage = AgentUsage.zero
    private var toolCalls: [String: ToolCallBuilder] = [:]
    private var responseItems: [String: AgentValue] = [:]
    private var lastEmittedSnapshot = AgentStreamSnapshot()
    private var didTerminateNormally = false

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func markDone() {
        if !didTerminateNormally {
            finishReason = finishReason ?? "stop"
        }
        didTerminateNormally = true
    }

    func consume(_ event: AgentValue) throws -> AgentStreamSnapshot? {
        guard let object = event.objectValue else { return nil }
        let type = object["type"]?.stringValue ?? ""

        switch type {
        case "response.output_text.delta":
            content += object["delta"]?.stringValue ?? ""
        case "response.output_text.done":
            replaceWithLonger(&content, object["text"]?.stringValue)
        case "response.refusal.delta":
            content += object["delta"]?.stringValue ?? ""
        case "response.refusal.done":
            replaceWithLonger(
                &content,
                object["refusal"]?.stringValue ?? object["text"]?.stringValue
            )
        case "response.reasoning_summary_text.delta",
             "response.reasoning_text.delta",
             "response.reasoning.delta":
            reasoning += object["delta"]?.stringValue ?? ""
        case "response.reasoning_summary_text.done",
             "response.reasoning_text.done",
             "response.reasoning.done":
            replaceWithLonger(&reasoning, object["text"]?.stringValue)
        case "response.output_item.added", "response.output_item.done":
            if let item = object["item"] {
                try consumeOutputItem(
                    item,
                    outputIndex: Self.integer(object["output_index"]) ?? toolCalls.count
                )
            }
        case "response.function_call_arguments.delta":
            let key = resolvedToolKey(
                itemID: object["item_id"]?.stringValue,
                outputIndex: Self.integer(object["output_index"])
            )
            var builder = toolCalls[key] ?? ToolCallBuilder(
                order: Self.integer(object["output_index"]) ?? toolCalls.count
            )
            builder.itemID = object["item_id"]?.stringValue ?? builder.itemID
            builder.arguments += object["delta"]?.stringValue ?? ""
            toolCalls[key] = builder
        case "response.function_call_arguments.done":
            let key = resolvedToolKey(
                itemID: object["item_id"]?.stringValue,
                outputIndex: Self.integer(object["output_index"])
            )
            var builder = toolCalls[key] ?? ToolCallBuilder(
                order: Self.integer(object["output_index"]) ?? toolCalls.count
            )
            builder.itemID = object["item_id"]?.stringValue ?? builder.itemID
            replaceWithLonger(&builder.arguments, object["arguments"]?.stringValue)
            toolCalls[key] = builder
        case "response.completed":
            didTerminateNormally = true
            finishReason = "stop"
            if let response = object["response"] {
                try consumeResponse(response)
            }
        case "response.incomplete":
            didTerminateNormally = true
            finishReason = "length"
            if let response = object["response"] {
                try consumeResponse(response)
            }
        case "response.failed":
            throw providerFailure(from: object["response"] ?? event)
        case "error":
            let message = ProviderReasoningText.text(from: object["error"])
                ?? object["message"]?.stringValue
                ?? "Responses stream failed."
            throw OpenAICompatibleClientError.transport(
                OpenAIResponseSecretRedactor.redact(message, apiKey: apiKey)
            )
        default:
            if object["output"] != nil || object["usage"] != nil {
                try consumeResponse(event)
            }
        }

        let snapshot = safeSnapshot()
        guard !snapshot.isEmpty, snapshot != lastEmittedSnapshot else { return nil }
        lastEmittedSnapshot = snapshot
        return snapshot
    }

    func response(requireNormalTermination: Bool = false) throws -> AgentChatResponse {
        guard !requireNormalTermination || didTerminateNormally else {
            throw OpenAICompatibleClientError.transport(
                "Responses stream ended before response.completed or response.incomplete."
            )
        }
        let calls = toolCalls.values.sorted { lhs, rhs in
            if lhs.order == rhs.order { return lhs.itemID < rhs.itemID }
            return lhs.order < rhs.order
        }.map { builder in
            AgentToolCall(
                id: builder.callID.isEmpty ? builder.itemID : builder.callID,
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

        let snapshot = safeSnapshot(isFinal: true)
        guard !snapshot.isEmpty || !calls.isEmpty else {
            throw OpenAICompatibleClientError.emptyChoices
        }
        return AgentChatResponse(
            message: AgentMessage(
                role: .assistant,
                content: snapshot.content.isEmpty ? nil : snapshot.content,
                reasoningContent: snapshot.reasoningContent.isEmpty
                    ? nil
                    : snapshot.reasoningContent,
                providerMetadata: safeProviderMetadata(),
                toolCalls: calls
            ),
            usage: usage,
            finishReason: calls.isEmpty ? finishReason : "tool_calls"
        )
    }

    private func consumeResponse(_ value: AgentValue) throws {
        guard let object = value.objectValue else { return }
        switch object["status"]?.stringValue {
        case "completed":
            didTerminateNormally = true
            finishReason = finishReason ?? "stop"
        case "incomplete":
            didTerminateNormally = true
            finishReason = "length"
        case "failed":
            throw providerFailure(from: value)
        default:
            break
        }
        for (index, item) in (object["output"]?.arrayValue ?? []).enumerated() {
            try consumeOutputItem(item, outputIndex: index)
        }
        if let usage = object["usage"]?.objectValue {
            let inputTokens = Self.integer(usage["input_tokens"]) ?? 0
            let outputTokens = Self.integer(usage["output_tokens"]) ?? 0
            let totalTokens = Self.integer(usage["total_tokens"])
                ?? AgentUsage.saturatingSum(inputTokens, outputTokens)
            let cachedTokens = Self.integer(
                usage["input_tokens_details"]?.objectValue?["cached_tokens"]
            ) ?? 0
            guard inputTokens >= 0, outputTokens >= 0, totalTokens >= 0, cachedTokens >= 0 else {
                throw OpenAICompatibleClientError.invalidUsage
            }
            self.usage = AgentUsage(
                promptTokens: inputTokens,
                completionTokens: outputTokens,
                totalTokens: totalTokens,
                cachedTokens: cachedTokens
            )
        }
    }

    private func consumeOutputItem(_ value: AgentValue, outputIndex: Int) throws {
        guard let item = value.objectValue else { return }
        switch item["type"]?.stringValue {
        case "message":
            for part in item["content"]?.arrayValue ?? [] {
                guard let part = part.objectValue else { continue }
                switch part["type"]?.stringValue {
                case "output_text", "text":
                    replaceWithLonger(&content, part["text"]?.stringValue)
                case "refusal":
                    replaceWithLonger(
                        &content,
                        part["refusal"]?.stringValue ?? part["text"]?.stringValue
                    )
                default:
                    break
                }
            }
        case "reasoning":
            let itemID = item["id"]?.stringValue ?? "reasoning_\(outputIndex)"
            responseItems[String(format: "%08d:%@", outputIndex, itemID)] = value
            if let summary = ProviderReasoningText.text(from: item["summary"]) {
                replaceWithLonger(&reasoning, summary)
            }
        case "function_call":
            let itemID = item["id"]?.stringValue ?? "function_\(outputIndex)"
            let key = resolvedToolKey(itemID: itemID, outputIndex: outputIndex)
            var builder = toolCalls[key] ?? ToolCallBuilder(order: outputIndex)
            builder.itemID = itemID
            builder.callID = item["call_id"]?.stringValue ?? builder.callID
            builder.name = item["name"]?.stringValue ?? builder.name
            replaceWithLonger(&builder.arguments, item["arguments"]?.stringValue)
            toolCalls[key] = builder
        default:
            break
        }
    }

    private func safeSnapshot(isFinal: Bool = false) -> AgentStreamSnapshot {
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
        return AgentStreamSnapshot(
            content: redact(content),
            reasoningContent: redact(reasoning)
        )
    }

    private func safeProviderMetadata() -> AgentValue? {
        guard !responseItems.isEmpty else { return nil }
        let metadata = AgentValue.object([
            "openai_response_items": .array(
                responseItems.keys.sorted().compactMap { responseItems[$0] }
            ),
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

    private func resolvedToolKey(itemID: String?, outputIndex: Int?) -> String {
        let indexKey = "index:\(outputIndex ?? toolCalls.count)"
        guard let itemID, !itemID.isEmpty else { return indexKey }
        if toolCalls[itemID] == nil, let indexedBuilder = toolCalls.removeValue(forKey: indexKey) {
            toolCalls[itemID] = indexedBuilder
        }
        return itemID
    }

    private func replaceWithLonger(_ target: inout String, _ candidate: String?) {
        guard let candidate, candidate.count >= target.count else { return }
        target = candidate
    }

    private func providerFailure(from value: AgentValue) -> OpenAICompatibleClientError {
        let object = value.objectValue
        let error = object?["error"]?.objectValue
        let message = error?["message"]?.stringValue
            ?? object?["message"]?.stringValue
            ?? "Responses request failed."
        let code = error?["code"]?.stringValue ?? object?["code"]?.stringValue
        let detail = code.map { "Responses request failed (\($0)): \(message)" }
            ?? "Responses request failed: \(message)"
        return .transport(OpenAIResponseSecretRedactor.redact(detail, apiKey: apiKey))
    }

    private static func integer(_ value: AgentValue?) -> Int? {
        guard let number = value?.numberValue,
              number.isFinite,
              number >= Double(Int.min),
              number <= Double(Int.max) else { return nil }
        return Int(number)
    }
}
