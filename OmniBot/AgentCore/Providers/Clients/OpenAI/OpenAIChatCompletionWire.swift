import Foundation

nonisolated struct OpenAIChatCompletionRequestBody: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        struct ToolCall: Encodable, Sendable {
            struct Function: Encodable, Sendable {
                let name: String
                let arguments: String
            }

            let id: String
            let type: String
            let function: Function
        }

        let role: String
        let content: String?
        let reasoningContent: String?
        let toolCalls: [ToolCall]?
        let toolCallID: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
            case name
        }

        init(_ message: AgentMessage, includeReasoning: Bool) {
            role = message.role.rawValue
            content = message.content
            reasoningContent = includeReasoning ? message.reasoningContent : nil
            toolCalls = message.toolCalls.isEmpty ? nil : message.toolCalls.map {
                ToolCall(
                    id: $0.id,
                    type: "function",
                    function: .init(name: $0.name, arguments: $0.arguments)
                )
            }
            toolCallID = message.toolCallID
            name = message.name
        }
    }

    struct Tool: Encodable, Sendable {
        struct Function: Encodable, Sendable {
            let name: String
            let description: String
            let parameters: AgentValue
        }

        let type: String
        let function: Function

        init(_ definition: AgentToolDefinition) {
            type = "function"
            function = Function(
                name: definition.name,
                description: definition.description,
                parameters: definition.parameters
            )
        }
    }

    let model: String
    let messages: [Message]
    let tools: [Tool]?
    let temperature: Double?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let reasoningEffort: AgentReasoningEffort?
    let enableThinking: Bool?
    let thinking: Thinking?
    let stream: Bool
    let streamOptions: StreamOptions?

    struct StreamOptions: Encodable, Sendable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    struct Thinking: Encodable, Sendable {
        let type: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case tools
        case temperature
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
        case enableThinking = "enable_thinking"
        case thinking
        case stream
        case streamOptions = "stream_options"
    }

    init(_ request: AgentChatRequest, protocolType: ProviderProtocolType) {
        model = request.model
        messages = request.messages.map {
            Message($0, includeReasoning: protocolType == .deepSeek)
        }
        tools = request.tools.isEmpty ? nil : request.tools.map(Tool.init)
        let disablesReasoning = request.reasoningEffort == .no
        let hasReasoningEffort = request.reasoningEffort != nil && !disablesReasoning
        let isDeepSeekReasoning = protocolType == .deepSeek && hasReasoningEffort
        temperature = isDeepSeekReasoning ? nil : request.temperature
        maxTokens = protocolType == .deepSeek || !hasReasoningEffort
            ? request.maxTokens
            : nil
        maxCompletionTokens = protocolType == .openAICompatible
            && hasReasoningEffort
            ? request.maxTokens
            : nil
        switch protocolType {
        case .deepSeek:
            reasoningEffort = Self.deepSeekEffort(request.reasoningEffort)
            enableThinking = disablesReasoning ? false : nil
            thinking = disablesReasoning
                ? Thinking(type: "disabled")
                : (hasReasoningEffort ? Thinking(type: "enabled") : nil)
        case .openAICompatible:
            reasoningEffort = disablesReasoning ? nil : request.reasoningEffort
            enableThinking = disablesReasoning ? false : nil
            thinking = nil
        case .anthropic:
            reasoningEffort = nil
            enableThinking = nil
            thinking = nil
        }
        stream = request.stream
        streamOptions = request.stream ? StreamOptions(includeUsage: true) : nil
    }

    private static func deepSeekEffort(
        _ effort: AgentReasoningEffort?
    ) -> AgentReasoningEffort? {
        switch effort {
        case .low, .medium, .high:
            .high
        case .xhigh, .max:
            .max
        case .no, nil:
            nil
        }
    }
}

nonisolated struct OpenAIChatCompletionResponseBody: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            struct ToolCall: Decodable, Sendable {
                struct Function: Decodable, Sendable {
                    let name: String
                    let arguments: String

                    enum CodingKeys: CodingKey {
                        case name
                        case arguments
                    }

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        name = try container.decode(String.self, forKey: .name)
                        if let string = try? container.decode(String.self, forKey: .arguments) {
                            arguments = string
                        } else {
                            let value = try container.decode(AgentValue.self, forKey: .arguments)
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                            arguments = String(
                                data: try encoder.encode(value),
                                encoding: .utf8
                            ) ?? "{}"
                        }
                    }
                }

                let id: String
                let function: Function
            }

            let role: String?
            let content: String?
            let reasoningContent: AgentValue?
            let reasoning: AgentValue?
            let thinking: AgentValue?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case role
                case content
                case reasoningContent = "reasoning_content"
                case reasoning
                case thinking
                case toolCalls = "tool_calls"
            }
        }

        let message: Message
        let reasoningContent: AgentValue?
        let reasoning: AgentValue?
        let thinking: AgentValue?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case reasoningContent = "reasoning_content"
            case reasoning
            case thinking
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable, Sendable {
        struct PromptTokensDetails: Decodable, Sendable {
            let cachedTokens: Int?

            enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int?
        let promptTokensDetails: PromptTokensDetails?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
        }
    }

    let choices: [Choice]
    let usage: Usage?
}

nonisolated struct OpenAIChatCompletionStreamChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            struct ToolCall: Decodable, Sendable {
                struct Function: Decodable, Sendable {
                    let name: String?
                    let arguments: String?
                }

                let index: Int
                let id: String?
                let function: Function?
            }

            let content: String?
            let reasoningContent: AgentValue?
            let reasoning: AgentValue?
            let thinking: AgentValue?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
                case reasoning
                case thinking
                case toolCalls = "tool_calls"
            }
        }

        let delta: Delta?
        let message: OpenAIChatCompletionResponseBody.Choice.Message?
        let reasoningContent: AgentValue?
        let reasoning: AgentValue?
        let thinking: AgentValue?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case message
            case reasoningContent = "reasoning_content"
            case reasoning
            case thinking
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
    let usage: OpenAIChatCompletionResponseBody.Usage?
}

nonisolated struct OpenAIErrorEnvelope: Decodable, Sendable {
    struct APIError: Decodable, Sendable {
        let message: String
        let type: String?
        let code: FlexibleString?
    }

    let error: APIError?
    let message: String?
}

nonisolated struct FlexibleString: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int.self) {
            value = String(integer)
        } else if let number = try? container.decode(Double.self) {
            value = String(number)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a string or number"
                )
            )
        }
    }
}
