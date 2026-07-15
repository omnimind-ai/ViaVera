import Foundation
import Testing
@testable import Via_Vera

@Suite(.serialized)
struct ProviderStreamTerminationTests {
    @Test func chatRejectsEOFBeforeTerminationWithoutReturningPartialToolCall() async throws {
        let body = try sseData(events: [[
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "id": "call_partial",
                        "function": [
                            "name": "file_read",
                            "arguments": #"{"path":"#,
                        ],
                    ]],
                ],
                "finish_reason": NSNull(),
            ]],
        ]])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: chatProfile(),
            session: stubSession()
        )

        do {
            _ = try await client.stream(streamRequest(), apiKey: "provider-key") { _ in }
            Issue.record("Expected a truncated Chat Completions stream to fail")
        } catch let error as OpenAICompatibleClientError {
            #expect(error.isRetryable)
            #expect(error.localizedDescription.contains("normal termination signal"))
        }
    }

    @Test func responsesRejectsEOFBeforeTerminationWithoutReturningPartialToolCall() async throws {
        let body = try sseData(events: [
            [
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "type": "function_call",
                    "id": "fc_partial",
                    "call_id": "call_partial",
                    "name": "file_read",
                    "arguments": "",
                ],
            ],
            [
                "type": "response.function_call_arguments.delta",
                "output_index": 0,
                "item_id": "fc_partial",
                "delta": #"{"path":"#,
            ],
        ])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAIResponsesClient(
            profile: responsesProfile(),
            session: stubSession()
        )

        do {
            _ = try await client.stream(streamRequest(), apiKey: "provider-key") { _ in }
            Issue.record("Expected a truncated Responses stream to fail")
        } catch let error as OpenAICompatibleClientError {
            #expect(error.isRetryable)
            #expect(error.localizedDescription.contains("response.completed"))
        }
    }

    @Test func responsesAcceptsGatewayDoneAsExplicitTermination() async throws {
        let body = try sseData(
            events: [[
                "type": "response.output_text.delta",
                "delta": "Gateway result",
            ]],
            includesDone: true
        )
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAIResponsesClient(
            profile: responsesProfile(),
            session: stubSession()
        )
        let result = try await client.stream(streamRequest(), apiKey: "provider-key") { _ in }

        #expect(result.message.content == "Gateway result")
        #expect(result.finishReason == "stop")
    }

    @Test func anthropicRejectsEOFBeforeMessageStopWithoutReturningPartialToolCall() async throws {
        let body = try sseData(events: [
            [
                "type": "content_block_start",
                "index": 0,
                "content_block": [
                    "type": "tool_use",
                    "id": "toolu_partial",
                    "name": "file_read",
                    "input": [:],
                ],
            ],
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": #"{"path":"#,
                ],
            ],
        ])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = AnthropicMessagesClient(
            profile: anthropicProfile(),
            session: stubSession()
        )

        do {
            _ = try await client.stream(streamRequest(), apiKey: "provider-key") { _ in }
            Issue.record("Expected a truncated Anthropic stream to fail")
        } catch let error as OpenAICompatibleClientError {
            #expect(error.isRetryable)
            #expect(error.localizedDescription.contains("message_stop"))
        }
    }

    @Test func anthropicRejectsInvalidNonemptyPartialJSONAfterMessageStop() async throws {
        let apiKey = "anthropic-secret-key"
        let body = try sseData(events: [
            [
                "type": "content_block_start",
                "index": 0,
                "content_block": [
                    "type": "tool_use",
                    "id": "toolu_invalid",
                    "name": "file_read",
                    "input": [:],
                ],
            ],
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": [
                    "type": "input_json_delta",
                    "partial_json": #"{"token":"anthropic-secret-key""#,
                ],
            ],
            [
                "type": "message_delta",
                "delta": ["stop_reason": "tool_use"],
            ],
            ["type": "message_stop"],
        ])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = AnthropicMessagesClient(
            profile: anthropicProfile(),
            session: stubSession()
        )

        do {
            _ = try await client.stream(streamRequest(), apiKey: apiKey) { _ in }
            Issue.record("Expected malformed Anthropic partial_json to fail")
        } catch let error as OpenAICompatibleClientError {
            #expect(!error.localizedDescription.contains(apiKey))
            #expect(error.localizedDescription.contains("incomplete or invalid JSON"))
        }
    }

    @Test func chatSupportsMessageOnlyCompleteSnapshots() async throws {
        let body = try sseData(events: [[
            "choices": [[
                "message": [
                    "role": "assistant",
                    "content": "Complete answer",
                    "reasoning_content": "Complete reasoning",
                    "tool_calls": [[
                        "id": "call_complete",
                        "function": [
                            "name": "file_read",
                            "arguments": #"{"path":"README.md"}"#,
                        ],
                    ]],
                ],
                "finish_reason": "tool_calls",
            ]],
        ]])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: chatProfile(),
            session: stubSession()
        )
        let result = try await client.stream(streamRequest(), apiKey: "provider-key") { _ in }

        #expect(result.message.content == "Complete answer")
        #expect(result.message.reasoningContent == "Complete reasoning")
        #expect(result.message.toolCalls == [
            AgentToolCall(
                id: "call_complete",
                name: "file_read",
                arguments: #"{"path":"README.md"}"#
            ),
        ])
    }

    @Test func chatMergesStandardDeltasAndRepeatedCompleteToolSnapshots() async throws {
        let body = try sseData(
            events: [
                [
                    "choices": [[
                        "delta": [
                            "tool_calls": [[
                                "index": 0,
                                "id": "call_",
                                "function": [
                                    "name": "file_",
                                    "arguments": #"{"path":"#,
                                ],
                            ]],
                        ],
                        "finish_reason": NSNull(),
                    ]],
                ],
                [
                    "choices": [[
                        "delta": [
                            "tool_calls": [[
                                "index": 0,
                                "id": "call_read",
                                "function": [
                                    "name": "file_read",
                                    "arguments": #"{"path":"README.md"}"#,
                                ],
                            ]],
                        ],
                        "finish_reason": "tool_calls",
                    ]],
                ],
            ],
            includesDone: true
        )
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: chatProfile(),
            session: stubSession()
        )
        let result = try await client.stream(streamRequest(), apiKey: "provider-key") { _ in }

        #expect(result.message.toolCalls == [
            AgentToolCall(
                id: "call_read",
                name: "file_read",
                arguments: #"{"path":"README.md"}"#
            ),
        ])
    }

    @Test func qwenBuffersLeadingInlineThinkingUntilSplitClosingTag() async throws {
        let body = try sseData(events: [
            [
                "choices": [[
                    "delta": ["content": "private reasoning"],
                    "finish_reason": NSNull(),
                ]],
            ],
            [
                "choices": [[
                    "delta": ["content": "</think>answer"],
                    "finish_reason": "stop",
                ]],
            ],
        ])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: chatProfile(),
            session: stubSession()
        )
        let recorder = ProviderTerminationSnapshotRecorder()
        let result = try await client.stream(
            streamRequest(model: "vendor/qwen3-235b"),
            apiKey: "provider-key"
        ) { snapshot in
            await recorder.append(snapshot)
        }

        #expect(result.message.reasoningContent == "private reasoning")
        #expect(result.message.content == "answer")
        let snapshots = await recorder.values()
        #expect(snapshots.first == AgentStreamSnapshot(
            content: "answer",
            reasoningContent: "private reasoning"
        ))
        #expect(snapshots.allSatisfy { !$0.content.contains("private reasoning") })
    }

    @Test func qwenFlushesOrdinaryLeadingAnswerAtNormalTermination() async throws {
        let body = try sseData(events: [[
            "choices": [[
                "delta": ["content": "Ordinary answer"],
                "finish_reason": "stop",
            ]],
        ]])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: chatProfile(),
            session: stubSession()
        )
        let result = try await client.stream(
            streamRequest(model: "qwen3-coder"),
            apiKey: "provider-key"
        ) { _ in }

        #expect(result.message.content == "Ordinary answer")
        #expect(result.message.reasoningContent == nil)
    }

    @Test func qwenReleasesLeadingBufferAfterSixContentChunks() async throws {
        var events: [[String: Any]] = (0..<6).map { _ in
            [
                "choices": [[
                    "delta": ["content": "a"],
                    "finish_reason": NSNull(),
                ]],
            ]
        }
        events.append([
            "choices": [[
                "delta": [:],
                "finish_reason": "stop",
            ]],
        ])
        let body = try sseData(events: events)
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAICompatibleClient(
            profile: chatProfile(),
            session: stubSession()
        )
        let recorder = ProviderTerminationSnapshotRecorder()
        let result = try await client.stream(
            streamRequest(model: "qwen-long-answer"),
            apiKey: "provider-key"
        ) { snapshot in
            await recorder.append(snapshot)
        }

        #expect(result.message.content == "aaaaaa")
        #expect(await recorder.values().first?.content == "aaaaaa")
    }

    @Test func anthropicManualThinkingRaisesSmallLimitAndHaikuOmitsInterleavedBeta() async throws {
        let capture = ProviderTerminationRequestCapture()
        let body = try sseData(events: [
            [
                "type": "content_block_start",
                "index": 0,
                "content_block": ["type": "text", "text": ""],
            ],
            [
                "type": "content_block_delta",
                "index": 0,
                "delta": ["type": "text_delta", "text": "Limit reached"],
            ],
            [
                "type": "message_delta",
                "delta": ["stop_reason": "model_context_window_exceeded"],
            ],
            ["type": "message_stop"],
        ])
        install(body: body, capture: capture)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = AnthropicMessagesClient(
            profile: anthropicProfile(),
            session: stubSession()
        )
        let request = AgentChatRequest(
            runID: UUID(),
            model: "claude-haiku-4-5-20251001",
            messages: [.user("Inspect")],
            tools: [toolDefinition()],
            maxTokens: 1_024,
            reasoningEffort: .medium,
            stream: true
        )
        let result = try await client.stream(request, apiKey: "anthropic-key") { _ in }

        #expect(result.finishReason == "length")
        let sentRequest = try #require(capture.value())
        #expect(sentRequest.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let data = try #require(capture.bodyData())
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["max_tokens"] as? Int == 1_025)
        let thinking = try #require(payload["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "enabled")
        #expect(thinking["budget_tokens"] as? Int == 1_024)
        #expect(payload["output_config"] == nil)
    }

    @Test func responsesFailedRejectsPartialResultAndRedactsCredential() async throws {
        let apiKey = "responses-secret-key"
        let body = try sseData(events: [
            [
                "type": "response.output_text.delta",
                "delta": "Partial answer",
            ],
            [
                "type": "response.failed",
                "response": [
                    "status": "failed",
                    "error": [
                        "code": "server_error",
                        "message": "Failure echoed \(apiKey)",
                    ],
                ],
            ],
        ])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAIResponsesClient(
            profile: responsesProfile(),
            session: stubSession()
        )

        do {
            _ = try await client.stream(streamRequest(), apiKey: apiKey) { _ in }
            Issue.record("Expected response.failed to reject the partial result")
        } catch let error as OpenAICompatibleClientError {
            #expect(error.localizedDescription.contains("server_error"))
            #expect(error.localizedDescription.contains(OpenAIResponseSecretRedactor.replacement))
            #expect(!error.localizedDescription.contains(apiKey))
        }
    }

    @Test func responsesStreamsRefusalAsVisibleAssistantContent() async throws {
        let refusal = "I can’t help with that."
        let body = try sseData(events: [
            [
                "type": "response.refusal.delta",
                "delta": "I can’t help",
            ],
            [
                "type": "response.refusal.done",
                "refusal": refusal,
            ],
            [
                "type": "response.completed",
                "response": [
                    "status": "completed",
                    "output": [[
                        "type": "message",
                        "content": [[
                            "type": "refusal",
                            "refusal": refusal,
                        ]],
                    ]],
                ],
            ],
        ])
        install(body: body)
        defer { ProviderTerminationURLProtocolStub.setHandler(nil) }

        let client = OpenAIResponsesClient(
            profile: responsesProfile(),
            session: stubSession()
        )
        let result = try await client.stream(streamRequest(), apiKey: "provider-key") { _ in }

        #expect(result.message.content == refusal)
    }

    private func streamRequest(model: String = "test-model") -> AgentChatRequest {
        AgentChatRequest(
            runID: UUID(),
            model: model,
            messages: [.user("Test")],
            stream: true
        )
    }

    private func chatProfile() -> ProviderProfile {
        ProviderProfile(
            id: "termination-chat",
            name: "Chat",
            baseURL: URL(string: "https://provider.example/v1")!
        )
    }

    private func responsesProfile() -> ProviderProfile {
        ProviderProfile(
            id: "termination-responses",
            name: "Responses",
            baseURL: URL(string: "https://provider.example/v1")!,
            wireAPI: .responses
        )
    }

    private func anthropicProfile() -> ProviderProfile {
        ProviderProfile(
            id: "termination-anthropic",
            name: "Anthropic",
            baseURL: URL(string: "https://api.anthropic.com")!,
            protocolType: .anthropic
        )
    }

    private func toolDefinition() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_read",
            description: "Read a file",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string")]),
                ]),
            ])
        )
    }

    private func sseData(
        events: [[String: Any]],
        includesDone: Bool = false
    ) throws -> Data {
        var lines: [String] = []
        for event in events {
            let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            let text = try #require(String(data: data, encoding: .utf8))
            lines.append("data: \(text)")
        }
        if includesDone {
            lines.append("data: [DONE]")
        }
        return Data((lines.joined(separator: "\n\n") + "\n\n").utf8)
    }

    private func install(
        body: Data,
        capture: ProviderTerminationRequestCapture? = nil
    ) {
        ProviderTerminationURLProtocolStub.setHandler { request in
            capture?.store(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw ProviderTerminationStubError.invalidResponse
            }
            return (response, body)
        }
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderTerminationURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private actor ProviderTerminationSnapshotRecorder {
    private var snapshots: [AgentStreamSnapshot] = []

    func append(_ snapshot: AgentStreamSnapshot) {
        snapshots.append(snapshot)
    }

    func values() -> [AgentStreamSnapshot] {
        snapshots
    }
}

nonisolated private final class ProviderTerminationRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var body: Data?

    func store(_ request: URLRequest) {
        let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        lock.lock()
        self.request = request
        self.body = body
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

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }
                return stream.read(baseAddress, maxLength: rawBuffer.count)
            }
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return stream.streamError == nil ? result : nil
    }
}

nonisolated private final class ProviderTerminationURLProtocolStub: URLProtocol,
    @unchecked Sendable
{
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func setHandler(_ handler: Handler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

nonisolated private enum ProviderTerminationStubError: Error {
    case invalidResponse
}
