import Foundation
import Testing
@testable import Via_Vera

@Suite(.serialized)
struct OpenAICompatibleClientTests {
    @Test func streamsTextAndCapturesPerTurnCacheUsage() async throws {
        let capture = RequestCapture()
        URLProtocolStub.setHandler { request in
            capture.store(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = """
            data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}],"usage":null}

            data: {"choices":[{"delta":{"content":" world"},"finish_reason":"stop"}],"usage":null}

            data: {"choices":[],"usage":{"prompt_tokens":20,"completion_tokens":2,"total_tokens":22,"prompt_tokens_details":{"cached_tokens":8,"cache_write_tokens":3}}}

            data: [DONE]

            """
            return (response, Data(body.utf8))
        }
        defer { URLProtocolStub.setHandler(nil) }

        let profile = ProviderProfile(
            id: "stream-test",
            name: "Stream Test",
            baseURL: try #require(URL(string: "https://provider.example/v1"))
        )
        let client = OpenAICompatibleClient(profile: profile, session: makeStubSession())
        let recorder = SnapshotRecorder()
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [.user("Hello")],
            promptCacheKey: "conversation-cache-key",
            stream: true
        )

        let result = try await client.stream(request, apiKey: "secret-key") { snapshot in
            await recorder.append(snapshot.content)
        }

        #expect(result.message.content == "Hello world")
        #expect(result.usage.promptTokens == 12)
        #expect(result.usage.completionTokens == 2)
        #expect(result.usage.cachedTokens == 8)
        #expect(result.usage.cacheCreationTokens == 3)
        #expect(result.usage.reportsCacheUsage)
        #expect(await recorder.values().contains("Hello"))
        #expect(await recorder.values().last == "Hello world")

        let bodyData = try #require(capture.bodyData())
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        #expect(body["prompt_cache_key"] as? String == "conversation-cache-key")
        let streamOptions = try #require(body["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
    }

    @Test func assemblesToolCallsSplitAcrossStreamingChunks() async throws {
        URLProtocolStub.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = """
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_","function":{"name":"file_","arguments":"{\\\"path\\\":"}}]},"finish_reason":null}]}

            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"read","function":{"name":"read","arguments":"\\\"README.md\\\"}"}}]},"finish_reason":"tool_calls"}]}

            data: [DONE]

            """
            return (response, Data(body.utf8))
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "stream-tool-test",
                name: "Stream Tool Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [.user("Read the README")],
            stream: true
        )

        let result = try await client.stream(request, apiKey: "secret-key") { _ in }

        #expect(result.finishReason == "tool_calls")
        #expect(result.message.toolCalls == [
            AgentToolCall(
                id: "call_read",
                name: "file_read",
                arguments: #"{"path":"README.md"}"#
            )
        ])
    }

    @Test func streamsCumulativeChatCompletionsReasoningAndReturnsIt() async throws {
        let body = try makeSSEData([
            [
                "choices": [[
                    "delta": ["reasoning_content": "Check"],
                    "finish_reason": NSNull(),
                ]],
            ],
            [
                "choices": [[
                    "delta": ["reasoning_content": " the facts."],
                    "finish_reason": NSNull(),
                ]],
            ],
            [
                "choices": [[
                    "delta": ["content": "Final answer"],
                    "finish_reason": "stop",
                ]],
            ],
        ])
        URLProtocolStub.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "chat-reasoning-test",
                name: "Chat Reasoning Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )
        let recorder = AgentSnapshotRecorder()
        let result = try await client.stream(
            AgentChatRequest(
                runID: UUID(),
                model: "reasoning-model",
                messages: [.user("Solve this")],
                reasoningEffort: .medium,
                stream: true
            ),
            apiKey: "secret-key"
        ) { snapshot in
            await recorder.append(snapshot)
        }

        #expect(result.message.reasoningContent == "Check the facts.")
        #expect(result.message.content == "Final answer")
        let snapshots = await recorder.values()
        #expect(snapshots.first?.reasoningContent == "Check")
        #expect(snapshots.contains {
            $0.reasoningContent == "Check the facts." && $0.content.isEmpty
        })
        #expect(snapshots.last == AgentStreamSnapshot(
            content: "Final answer",
            reasoningContent: "Check the facts."
        ))
    }

    @Test func deepSeekReplaysAssistantReasoningAndEnablesThinking() async throws {
        let capture = RequestCapture()
        URLProtocolStub.setHandler { request in
            capture.store(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            return (response, Data(#"{"choices":[{"message":{"role":"assistant","content":"done","reasoning_content":"verified"},"finish_reason":"stop"}]}"#.utf8))
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "deepseek-test",
                name: "DeepSeek",
                baseURL: try #require(URL(string: "https://api.deepseek.com")),
                protocolType: .deepSeek
            ),
            session: makeStubSession()
        )
        let result = try await client.complete(
            AgentChatRequest(
                runID: UUID(),
                model: "deepseek-reasoner",
                messages: [
                    .user("Continue"),
                    .assistant("intermediate", reasoningContent: "earlier reasoning"),
                ],
                temperature: 0.7,
                maxTokens: 2_048,
                reasoningEffort: .medium
            ),
            apiKey: "deepseek-key"
        )

        #expect(result.message.reasoningContent == "verified")
        let sentRequest = try #require(capture.value())
        #expect(sentRequest.url?.path == "/v1/chat/completions")
        #expect(sentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-key")
        let bodyData = try #require(capture.bodyData())
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        let messages = try #require(requestBody["messages"] as? [[String: Any]])
        #expect(messages[1]["reasoning_content"] as? String == "earlier reasoning")
        #expect((requestBody["thinking"] as? [String: Any])?["type"] as? String == "enabled")
        #expect(requestBody["reasoning_effort"] as? String == "high")
        #expect(requestBody["temperature"] == nil)
        #expect(requestBody["max_tokens"] as? Int == 2_048)
        #expect(requestBody["max_completion_tokens"] == nil)
    }

    @Test func responsesMapsHistoryAndStreamsReasoningTextToolsAndUsage() async throws {
        let capture = RequestCapture()
        let body = try makeSSEData([
            [
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "type": "reasoning",
                    "id": "rs_1",
                    "summary": [],
                ],
            ],
            [
                "type": "response.reasoning_summary_text.delta",
                "item_id": "rs_1",
                "delta": "Inspect carefully.",
            ],
            [
                "type": "response.output_text.delta",
                "delta": "Done",
            ],
            [
                "type": "response.output_item.added",
                "output_index": 2,
                "item": [
                    "type": "function_call",
                    "id": "fc_1",
                    "call_id": "call_1",
                    "name": "file_read",
                    "arguments": "",
                ],
            ],
            [
                "type": "response.function_call_arguments.delta",
                "output_index": 2,
                "item_id": "fc_1",
                "delta": #"{"path":"#,
            ],
            [
                "type": "response.function_call_arguments.delta",
                "output_index": 2,
                "item_id": "fc_1",
                "delta": #"README.md"}"#,
            ],
            [
                "type": "response.completed",
                "response": [
                    "status": "completed",
                    "output": [
                        [
                            "type": "reasoning",
                            "id": "rs_1",
                            "summary": [[
                                "type": "summary_text",
                                "text": "Inspect carefully.",
                            ]],
                        ],
                        [
                            "type": "message",
                            "id": "msg_1",
                            "content": [["type": "output_text", "text": "Done"]],
                        ],
                        [
                            "type": "function_call",
                            "id": "fc_1",
                            "call_id": "call_1",
                            "name": "file_read",
                            "arguments": #"{"path":"README.md"}"#,
                        ],
                    ],
                    "usage": [
                        "input_tokens": 20,
                        "output_tokens": 8,
                        "total_tokens": 28,
                        "input_tokens_details": [
                            "cached_tokens": 5,
                            "cache_write_tokens": 2,
                        ],
                    ],
                ],
            ],
        ])
        URLProtocolStub.setHandler { request in
            capture.store(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let retainedResponseItem: AgentValue = .object([
            "type": .string("reasoning"),
            "id": .string("rs_previous"),
            "encrypted_content": .string("opaque"),
        ])
        let previousCall = AgentToolCall(
            id: "call_previous",
            name: "file_list",
            arguments: #"{"path":"."}"#
        )
        let client = OpenAIResponsesClient(
            profile: ProviderProfile(
                id: "responses-test",
                name: "OpenAI Responses",
                baseURL: try #require(URL(string: "https://api.openai.com/v1")),
                wireAPI: .responses,
                defaultHeaders: ["X-Project": "project-a"]
            ),
            session: makeStubSession()
        )
        let recorder = AgentSnapshotRecorder()
        let result = try await client.stream(
            AgentChatRequest(
                runID: UUID(),
                model: "gpt-reasoning",
                messages: [
                    .system("Follow project policy"),
                    .user("Inspect the project"),
                    .assistant(
                        "Earlier answer",
                        providerMetadata: .object([
                            "openai_response_items": .array([retainedResponseItem]),
                        ]),
                        toolCalls: [previousCall]
                    ),
                    .tool(
                        callID: previousCall.id,
                        name: previousCall.name,
                        content: #"{"files":[]}"#
                    ),
                ],
                tools: [
                    AgentToolDefinition(
                        name: "file_read",
                        description: "Read a file",
                        parameters: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "path": .object(["type": .string("string")]),
                            ]),
                        ])
                    ),
                ],
                maxTokens: 4_096,
                reasoningEffort: .high,
                stream: true
            ),
            apiKey: "openai-key"
        ) { snapshot in
            await recorder.append(snapshot)
        }

        #expect(result.message.content == "Done")
        #expect(result.message.reasoningContent == "Inspect carefully.")
        #expect(result.message.toolCalls == [
            AgentToolCall(
                id: "call_1",
                name: "file_read",
                arguments: #"{"path":"README.md"}"#
            ),
        ])
        #expect(result.usage == AgentUsage(
            promptTokens: 15,
            completionTokens: 8,
            totalTokens: 28,
            cachedTokens: 5,
            cacheCreationTokens: 2,
            reportsCacheUsage: true
        ))
        let responseItems = result.message.providerMetadata?
            .objectValue?["openai_response_items"]?.arrayValue
        #expect(responseItems?.contains { $0.objectValue?["id"]?.stringValue == "rs_1" } == true)
        let snapshots = await recorder.values()
        #expect(snapshots.contains { $0.reasoningContent == "Inspect carefully." })
        #expect(snapshots.last?.content == "Done")

        let sentRequest = try #require(capture.value())
        #expect(sentRequest.url?.path == "/v1/responses")
        #expect(sentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer openai-key")
        #expect(sentRequest.value(forHTTPHeaderField: "X-Project") == "project-a")
        let requestData = try #require(capture.bodyData())
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        #expect(requestBody["instructions"] as? String == "Follow project policy")
        #expect(requestBody["max_output_tokens"] as? Int == 4_096)
        #expect((requestBody["reasoning"] as? [String: Any])?["effort"] as? String == "high")
        #expect((requestBody["reasoning"] as? [String: Any])?["summary"] as? String == "auto")
        let input = try #require(requestBody["input"] as? [[String: Any]])
        #expect(input.map { $0["type"] as? String } == [
            nil,
            "reasoning",
            nil,
            "function_call",
            "function_call_output",
        ])
        #expect(input[3]["call_id"] as? String == "call_previous")
        #expect(input[4]["call_id"] as? String == "call_previous")
        let tools = try #require(requestBody["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "function")
        #expect(tools.first?["name"] as? String == "file_read")
        #expect(tools.first?["parameters"] as? [String: Any] != nil)
    }

    @Test func anthropicMapsMessagesHeadersAndStreamsThinkingTextToolsAndMetadata() async throws {
        let capture = RequestCapture()
        let body = try makeSSEData([
            [
                "type": "message_start",
                "message": [
                    "id": "msg_1",
                    "type": "message",
                    "role": "assistant",
                    "content": [],
                    "usage": [
                        "input_tokens": 12,
                        "output_tokens": 0,
                        "cache_read_input_tokens": 4,
                        "cache_creation_input_tokens": 6,
                    ],
                ],
            ],
            [
                "type": "content_block_start",
                "index": 0,
                "content_block": ["type": "thinking", "thinking": ""],
            ],
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "thinking_delta", "thinking": "Check inputs."],
            ],
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "signature_delta", "signature": "signed-thinking"],
            ],
            [
                "type": "content_block_start",
                "index": 1,
                "content_block": ["type": "text", "text": ""],
            ],
            [
                "type": "content_block_delta",
                "index": 1,
                "delta": ["type": "text_delta", "text": "Done"],
            ],
            [
                "type": "content_block_start",
                "index": 2,
                "content_block": [
                    "type": "tool_use",
                    "id": "toolu_1",
                    "name": "file_read",
                    "input": [:],
                ],
            ],
            [
                "type": "content_block_delta",
                "index": 2,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": #"{"path":"README.md"}"#,
                ],
            ],
            [
                "type": "message_delta",
                "delta": ["stop_reason": "tool_use"],
                "usage": ["output_tokens": 7],
            ],
            ["type": "message_stop"],
        ], includesDone: false)
        URLProtocolStub.setHandler { request in
            capture.store(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let priorCall = AgentToolCall(
            id: "toolu_previous",
            name: "file_list",
            arguments: #"{"path":"."}"#
        )
        let secondCall = AgentToolCall(
            id: "toolu_second",
            name: "file_read",
            arguments: #"{"path":"Package.swift"}"#
        )
        let client = AnthropicMessagesClient(
            profile: ProviderProfile(
                id: "anthropic-test",
                name: "Anthropic",
                baseURL: try #require(URL(string: "https://api.anthropic.com")),
                protocolType: .anthropic,
                defaultHeaders: [
                    "X-Team": "team-a",
                    "Authorization": "must-not-be-sent",
                ]
            ),
            session: makeStubSession()
        )
        let recorder = AgentSnapshotRecorder()
        let result = try await client.stream(
            AgentChatRequest(
                runID: UUID(),
                model: "claude-sonnet-4-1",
                messages: [
                    .system("Be concise"),
                    .user("Inspect files"),
                    .assistant("I will inspect", toolCalls: [priorCall, secondCall]),
                    .tool(
                        callID: priorCall.id,
                        name: priorCall.name,
                        content: #"{"files":[]}"#
                    ),
                    .tool(
                        callID: secondCall.id,
                        name: secondCall.name,
                        content: "contents"
                    ),
                ],
                tools: [
                    AgentToolDefinition(
                        name: "file_read",
                        description: "Read a file",
                        parameters: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "path": .object(["type": .string("string")]),
                            ]),
                        ])
                    ),
                ],
                temperature: 0.6,
                maxTokens: 4_096,
                reasoningEffort: .high,
                promptCacheKey: "anthropic-conversation-cache",
                stream: true
            ),
            apiKey: "anthropic-key"
        ) { snapshot in
            await recorder.append(snapshot)
        }

        #expect(result.message.reasoningContent == "Check inputs.")
        #expect(result.message.content == "Done")
        #expect(result.message.toolCalls == [
            AgentToolCall(
                id: "toolu_1",
                name: "file_read",
                arguments: #"{"path":"README.md"}"#
            ),
        ])
        #expect(result.usage == AgentUsage(
            promptTokens: 18,
            completionTokens: 7,
            totalTokens: 29,
            cachedTokens: 4,
            cacheCreationTokens: 6,
            reportsCacheUsage: true
        ))
        #expect(result.finishReason == "tool_calls")
        let metadataBlocks = result.message.providerMetadata?
            .objectValue?["anthropic_content"]?.arrayValue
        #expect(metadataBlocks?.map { $0.objectValue?["type"]?.stringValue } == [
            "thinking",
            "text",
            "tool_use",
        ])
        #expect(metadataBlocks?.first?.objectValue?["signature"]?.stringValue == "signed-thinking")
        let snapshots = await recorder.values()
        #expect(snapshots.contains { $0.reasoningContent == "Check inputs." })
        #expect(snapshots.last == AgentStreamSnapshot(
            content: "Done",
            reasoningContent: "Check inputs."
        ))

        let sentRequest = try #require(capture.value())
        #expect(sentRequest.url?.path == "/v1/messages")
        #expect(sentRequest.value(forHTTPHeaderField: "x-api-key") == "anthropic-key")
        #expect(sentRequest.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sentRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(sentRequest.value(forHTTPHeaderField: "anthropic-beta") == "interleaved-thinking-2025-05-14")
        #expect(sentRequest.value(forHTTPHeaderField: "X-Team") == "team-a")
        let requestData = try #require(capture.bodyData())
        let requestBody = try #require(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        let system = try #require(requestBody["system"] as? [[String: Any]])
        #expect(system.first?["text"] as? String == "Be concise")
        #expect(
            (system.first?["cache_control"] as? [String: Any])?["type"] as? String
                == "ephemeral"
        )
        #expect(requestBody["temperature"] == nil)
        #expect((requestBody["thinking"] as? [String: Any])?["type"] as? String == "enabled")
        #expect((requestBody["thinking"] as? [String: Any])?["budget_tokens"] as? Int == 4_095)
        #expect(requestBody["output_config"] == nil)
        let messages = try #require(requestBody["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let toolResults = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(toolResults.count == 2)
        #expect(toolResults.allSatisfy { $0["type"] as? String == "tool_result" })
        #expect(toolResults.first?["cache_control"] == nil)
        #expect(
            (toolResults.last?["cache_control"] as? [String: Any])?["type"] as? String
                == "ephemeral"
        )
        let tools = try #require(requestBody["tools"] as? [[String: Any]])
        #expect(tools.first?["input_schema"] as? [String: Any] != nil)
        #expect(
            (tools.first?["cache_control"] as? [String: Any])?["type"] as? String
                == "ephemeral"
        )
    }

    @Test func encodesToolHistoryAndDecodesAssistantToolCalls() async throws {
        let capture = RequestCapture()
        URLProtocolStub.setHandler { request in
            capture.store(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = #"""
            {
              "id": "chatcmpl-test",
              "choices": [{
                "index": 0,
                "message": {
                  "role": "assistant",
                  "content": null,
                  "tool_calls": [{
                    "id": "call_next",
                    "type": "function",
                    "function": {"name": "file_read", "arguments": "{\"path\":\"README.md\"}"}
                  }]
                },
                "finish_reason": "tool_calls"
              }],
              "usage": {"prompt_tokens": 20, "completion_tokens": 7, "total_tokens": 27}
            }
            """#.data(using: .utf8)!
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let profile = ProviderProfile(
            id: "test",
            name: "Test",
            baseURL: try #require(URL(string: "https://provider.example/v1")),
            defaultHeaders: ["X-Tenant": "tenant-a"]
        )
        let client = OpenAICompatibleClient(profile: profile, session: makeStubSession())
        let previousCall = AgentToolCall(
            id: "call_previous",
            name: "file_list",
            arguments: "{\"path\":\".\"}"
        )
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [
                .user("Inspect the project"),
                .assistant(toolCalls: [previousCall]),
                .tool(callID: previousCall.id, name: previousCall.name, content: "{\"files\":[]}")
            ],
            tools: [
                AgentToolDefinition(
                    name: "file_read",
                    description: "Read a file",
                    parameters: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object(["type": .string("string")])
                        ])
                    ])
                )
            ],
            temperature: 0.2,
            maxTokens: 2_048,
            stream: false
        )

        let result = try await client.complete(request, apiKey: "secret-key")

        #expect(result.finishReason == "tool_calls")
        #expect(result.usage == AgentUsage(promptTokens: 20, completionTokens: 7, totalTokens: 27))
        #expect(result.message.toolCalls == [
            AgentToolCall(
                id: "call_next",
                name: "file_read",
                arguments: "{\"path\":\"README.md\"}"
            )
        ])

        let sentRequest = try #require(capture.value())
        #expect(sentRequest.url?.path == "/v1/chat/completions")
        #expect(sentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
        #expect(sentRequest.value(forHTTPHeaderField: "X-Tenant") == "tenant-a")
        let bodyData = try #require(capture.bodyData())
        let body = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(body["runID"] == nil)
        #expect(body["stream"] as? Bool == false)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.allSatisfy { $0["id"] == nil })
        #expect((messages[1]["tool_calls"] as? [[String: Any]])?.count == 1)
        #expect(messages[2]["role"] as? String == "tool")
        #expect(messages[2]["tool_call_id"] as? String == "call_previous")
    }

    @Test func rejectsStreamingInsteadOfSilentlyChangingTheRequest() async throws {
        let profile = ProviderProfile(
            id: "test",
            name: "Test",
            baseURL: try #require(URL(string: "https://provider.example/v1"))
        )
        let client = OpenAICompatibleClient(profile: profile, session: makeStubSession())
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [.user("Hello")],
            stream: true
        )

        await #expect(throws: OpenAICompatibleClientError.streamingUnsupported) {
            try await client.complete(request, apiKey: "secret-key")
        }
    }

    @Test func refusesToSendBearerCredentialsToRemoteHTTP() async throws {
        let url = try #require(URL(string: "http://provider.example/v1"))
        #expect(throws: OpenAICompatibleClientError.invalidBaseURL(url)) {
            try OpenAICompatibleClient.chatCompletionsURL(for: url)
        }
    }

    @Test func immediateCancellationDoesNotWaitForDelayedTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedURLProtocolStub.self]
        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "cancel-test",
                name: "Cancel Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: URLSession(configuration: configuration)
        )
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [.user("Cancel immediately")]
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            // Enter complete() from an already-cancelled task. This makes the
            // create/register cancellation window deterministic.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.complete(request, apiKey: "secret-key")
        }

        do {
            _ = try await task.value
            Issue.record("Expected immediate cancellation")
        } catch is CancellationError {
            // Expected.
        }

        #expect(startedAt.duration(to: clock.now) < .seconds(1))
    }

    @Test func runIDCancellationCannotBeLostBeforeRequestRegistration() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedURLProtocolStub.self]
        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "run-id-cancel-test",
                name: "Run ID Cancel Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: URLSession(configuration: configuration)
        )
        let runID = UUID()
        let request = AgentChatRequest(
            runID: runID,
            model: "agent-model",
            messages: [.user("Cancel by run ID")]
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await client.complete(request, apiKey: "secret-key")
        }

        // Intentionally do not yield before cancelling. This exercises both
        // sides of the create/register race depending on task scheduling.
        await client.cancel(runID: runID)

        do {
            _ = try await task.value
            Issue.record("Expected run ID cancellation")
        } catch is CancellationError {
            // Expected.
        }
        #expect(startedAt.duration(to: clock.now) < .seconds(1))
    }

    @Test func parsesStructuredHTTPError() async throws {
        URLProtocolStub.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 429,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = #"""
            {
              "error": {
                "message": "Rate limit reached",
                "type": "rate_limit_error",
                "code": 42901
              }
            }
            """#.data(using: .utf8)!
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let profile = ProviderProfile(
            id: "test",
            name: "Test",
            baseURL: try #require(URL(string: "https://provider.example/v1"))
        )
        let client = OpenAICompatibleClient(profile: profile, session: makeStubSession())
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [.user("Hello")]
        )

        do {
            _ = try await client.complete(request, apiKey: "secret-key")
            Issue.record("Expected HTTP error")
        } catch let error as OpenAICompatibleClientError {
            guard case let .httpError(status, message, type, code, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(status == 429)
            #expect(message == "Rate limit reached")
            #expect(type == "rate_limit_error")
            #expect(code == "42901")
            #expect(error.localizedDescription.contains("Rate limit reached"))
        }
    }

    @Test func retriesWithoutPromptCacheKeyWhenACompatibleGatewayRejectsIt() async throws {
        let capture = RequestCapture()
        URLProtocolStub.setHandler { request in
            capture.store(request)
            guard let url = request.url else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = try #require(capture.bodyData())
            let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let includesCacheKey = object?["prompt_cache_key"] != nil
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: includesCacheKey ? 400 : 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            let data = includesCacheKey
                ? Data(#"{"error":{"message":"Unknown parameter: prompt_cache_key","type":"invalid_request_error"}}"#.utf8)
                : Data(#"{"choices":[{"message":{"role":"assistant","content":"fallback ok"},"finish_reason":"stop"}]}"#.utf8)
            return (response, data)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                name: "Compatible gateway",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )
        let result = try await client.complete(
            AgentChatRequest(
                runID: UUID(),
                model: "model",
                messages: [.user("Hello")],
                promptCacheKey: "stable-key"
            ),
            apiKey: "secret"
        )

        #expect(result.message.content == "fallback ok")
        #expect(capture.count() == 2)
        let finalBody = try #require(capture.bodyData())
        let finalObject = try #require(
            JSONSerialization.jsonObject(with: finalBody) as? [String: Any]
        )
        #expect(finalObject["prompt_cache_key"] == nil)
    }

    @Test func redactsEchoedCredentialsFromHTTPErrorFieldsAndBody() async throws {
        let apiKey = "sk-live-secret-12345"
        let secondaryToken = "secondary-token-98765"
        URLProtocolStub.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 401,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = try JSONSerialization.data(withJSONObject: [
                "error": [
                    "message": "Rejected Bearer \(apiKey); token=\(apiKey)",
                    "type": "authentication \(apiKey)",
                    "code": "key=\(apiKey)"
                ],
                "diagnostic": "Authorization: Bearer \(secondaryToken)"
            ])
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "redaction-test",
                name: "Redaction Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [.user("Hello")]
        )

        do {
            _ = try await client.complete(request, apiKey: apiKey)
            Issue.record("Expected HTTP error")
        } catch let error as OpenAICompatibleClientError {
            guard case let .httpError(_, message, type, code, body) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            let visibleValues = [message, type, code, body, error.localizedDescription]
                .compactMap { $0 }
            #expect(visibleValues.allSatisfy { !$0.contains(apiKey) })
            #expect(visibleValues.allSatisfy { !$0.contains(secondaryToken) })
            #expect(message.contains(OpenAIResponseSecretRedactor.replacement))
            #expect(body?.contains(OpenAIResponseSecretRedactor.replacement) == true)
        }
    }

    @Test func redactsCredentialVariantsFromSuccessfulAssistantContent() async throws {
        let apiKey = "sk-secret/value+42"
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        let percentEncoded = try #require(
            apiKey.addingPercentEncoding(withAllowedCharacters: unreserved)
        )
        let jsonEncoded = try {
            var value = try #require(
                String(data: JSONEncoder().encode(apiKey), encoding: .utf8)
            )
            value.removeFirst()
            value.removeLast()
            return value
        }()

        URLProtocolStub.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = try JSONSerialization.data(withJSONObject: [
                "choices": [[
                    "message": [
                        "role": "assistant",
                        "content": "exact=\(apiKey) json=\(jsonEncoded) url=\(percentEncoded)"
                    ],
                    "finish_reason": "stop"
                ]]
            ])
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "success-redaction-test",
                name: "Success Redaction Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )
        let result = try await client.complete(
            AgentChatRequest(
                runID: UUID(),
                model: "agent-model",
                messages: [.user("Hello")]
            ),
            apiKey: apiKey
        )
        let content = try #require(result.message.content)

        #expect(!content.contains(apiKey))
        #expect(!content.contains(jsonEncoded))
        #expect(!content.contains(percentEncoded))
        #expect(content.contains(OpenAIResponseSecretRedactor.replacement))
    }

    @Test func rejectsCredentialVariantsInEveryToolCallField() async throws {
        let apiKey = "sk-secret/value+42"
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        let percentEncoded = try #require(
            apiKey.addingPercentEncoding(withAllowedCharacters: unreserved)
        )
        let jsonEncoded = try {
            var value = try #require(
                String(data: JSONEncoder().encode(apiKey), encoding: .utf8)
            )
            value.removeFirst()
            value.removeLast()
            return value
        }()

        let cases = [
            (id: "call-\(apiKey)", name: "file_read", arguments: #"{"path":"README.md"}"#),
            (id: "call-name", name: "tool-\(jsonEncoded)", arguments: #"{"path":"README.md"}"#),
            (id: "call-arguments", name: "file_read", arguments: #"{"token":"\#(percentEncoded)"}"#),
            (
                id: "call-unicode-escaped-arguments",
                name: "file_read",
                arguments: #"{"token":"\u0073\u006b-secret/value+42"}"#
            )
        ]
        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "tool-redaction-test",
                name: "Tool Redaction Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )
        defer { URLProtocolStub.setHandler(nil) }

        for item in cases {
            URLProtocolStub.setHandler { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                      ) else {
                    throw URLProtocolStubError.invalidResponse
                }
                let body = try JSONSerialization.data(withJSONObject: [
                    "choices": [[
                        "message": [
                            "role": "assistant",
                            "content": NSNull(),
                            "tool_calls": [[
                                "id": item.id,
                                "type": "function",
                                "function": [
                                    "name": item.name,
                                    "arguments": item.arguments
                                ]
                            ]]
                        ],
                        "finish_reason": "tool_calls"
                    ]]
                ])
                return (response, body)
            }

            await #expect(throws: OpenAICompatibleClientError.credentialEchoInToolCall) {
                try await client.complete(
                    AgentChatRequest(
                        runID: UUID(),
                        model: "agent-model",
                        messages: [.user("Use a tool")]
                    ),
                    apiKey: apiKey
                )
            }
        }
    }

    @Test func preservesExistingChatCompletionsEndpoint() throws {
        let fullURL = try #require(URL(string: "https://provider.example/openai/v1/chat/completions"))
        #expect(try OpenAICompatibleClient.chatCompletionsURL(for: fullURL) == fullURL)
    }

    @Test func retriesOnlyTransientProviderFailures() {
        let body = Data(#"{"error":{"message":"temporary"}}"#.utf8)

        #expect(OpenAICompatibleClient.parseHTTPError(statusCode: 408, data: body).isRetryable)
        #expect(OpenAICompatibleClient.parseHTTPError(statusCode: 429, data: body).isRetryable)
        #expect(OpenAICompatibleClient.parseHTTPError(statusCode: 503, data: body).isRetryable)
        #expect(!OpenAICompatibleClient.parseHTTPError(statusCode: 401, data: body).isRetryable)
        #expect(!OpenAICompatibleClientError.responseDecodingFailed("bad JSON").isRetryable)
    }

    @Test func cancelsAndRejectsAResponseAtTheConfiguredByteLimit() async throws {
        #expect(OpenAIResponseTransport.defaultMaximumResponseBytes == 8 * 1024 * 1024)
        OversizedURLProtocolStub.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedURLProtocolStub.self]
        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "oversized-test",
                name: "Oversized Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: URLSession(configuration: configuration),
            maximumResponseBytes: 1_024
        )
        let request = AgentChatRequest(
            runID: UUID(),
            model: "agent-model",
            messages: [.user("Return too much data")]
        )

        do {
            _ = try await client.complete(request, apiKey: "secret-key")
            Issue.record("Expected oversized response rejection")
        } catch let error as OpenAICompatibleClientError {
            #expect(error == .responseTooLarge(maximumBytes: 1_024))
            #expect(!error.isRetryable)
        }

        for _ in 0..<100 where !OversizedURLProtocolStub.wasStopped {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(OversizedURLProtocolStub.wasStopped)
    }

    @Test func validatesAndSaturatesWireTokenUsage() async throws {
        URLProtocolStub.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = """
            {
              "choices": [{
                "message": {"role": "assistant", "content": "done"},
                "finish_reason": "stop"
              }],
              "usage": {
                "prompt_tokens": \(Int.max),
                "completion_tokens": \(Int.max)
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "usage-test",
                name: "Usage Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )
        let result = try await client.complete(
            AgentChatRequest(
                runID: UUID(),
                model: "agent-model",
                messages: [.user("Hello")]
            ),
            apiKey: "secret-key"
        )

        #expect(result.usage.promptTokens == .max)
        #expect(result.usage.completionTokens == .max)
        #expect(result.usage.totalTokens == .max)
    }

    @Test func rejectsNegativeWireTokenUsage() async throws {
        URLProtocolStub.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.invalidResponse
            }
            let body = Data((
                #"{"choices":[{"message":{"role":"assistant","content":"done"}}],"#
                    + #""usage":{"prompt_tokens":-1,"completion_tokens":1,"total_tokens":0}}"#
            ).utf8)
            return (response, body)
        }
        defer { URLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: ProviderProfile(
                id: "negative-usage-test",
                name: "Negative Usage Test",
                baseURL: try #require(URL(string: "https://provider.example/v1"))
            ),
            session: makeStubSession()
        )

        await #expect(throws: OpenAICompatibleClientError.invalidUsage) {
            try await client.complete(
                AgentChatRequest(
                    runID: UUID(),
                    model: "agent-model",
                    messages: [.user("Hello")]
                ),
                apiKey: "secret-key"
            )
        }
    }

    private func makeSSEData(
        _ events: [[String: Any]],
        includesDone: Bool = true
    ) throws -> Data {
        var lines: [String] = []
        for event in events {
            let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            let json = try #require(String(data: data, encoding: .utf8))
            lines.append("data: \(json)")
        }
        if includesDone {
            lines.append("data: [DONE]")
        }
        return Data((lines.joined(separator: "\n\n") + "\n\n").utf8)
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private actor SnapshotRecorder {
    private var snapshots: [String] = []

    func append(_ snapshot: String) {
        snapshots.append(snapshot)
    }

    func values() -> [String] {
        snapshots
    }
}

private actor AgentSnapshotRecorder {
    private var snapshots: [AgentStreamSnapshot] = []

    func append(_ snapshot: AgentStreamSnapshot) {
        snapshots.append(snapshot)
    }

    func values() -> [AgentStreamSnapshot] {
        snapshots
    }
}

nonisolated private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var body: Data?
    private var requestCount = 0

    func store(_ request: URLRequest) {
        let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        lock.lock()
        self.request = request
        self.body = body
        requestCount += 1
        lock.unlock()
    }

    func value() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func bodyData() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }
                return stream.read(baseAddress, maxLength: rawBuffer.count)
            }
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return stream.streamError == nil ? data : nil
    }
}

nonisolated private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func setHandler(_ handler: Handler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

nonisolated private enum URLProtocolStubError: Error {
    case invalidResponse
}

nonisolated private final class DelayedURLProtocolStub: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.shouldRespond(),
                  let url = self.request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                return
            }
            let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"late"},"finish_reason":"stop"}]}"#.utf8)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        lock.lock()
        stopped = false
        self.workItem = workItem
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        let workItem = self.workItem
        self.workItem = nil
        lock.unlock()
        workItem?.cancel()
    }

    private func shouldRespond() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped
    }
}

nonisolated private final class OversizedURLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stopped = false

    static var wasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    static func reset() {
        lock.lock()
        stopped = false
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLProtocolStubError.invalidResponse)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0x78, count: 2_048))
        // Keep the transfer open. The bounded transport must cancel it rather
        // than waiting for the endpoint to finish sending an unbounded body.
    }

    override func stopLoading() {
        Self.lock.lock()
        Self.stopped = true
        Self.lock.unlock()
    }
}
