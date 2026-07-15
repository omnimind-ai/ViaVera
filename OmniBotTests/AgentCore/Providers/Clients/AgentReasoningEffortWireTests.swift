import Foundation
import Testing
@testable import Via_Vera

@Suite("Reasoning effort wire mapping")
struct AgentReasoningEffortWireTests {
    @Test("DeepSeek disables thinking for no and maps maximum efforts")
    func deepSeekMapping() throws {
        let disabled = try encodedObject(
            OpenAIChatCompletionRequestBody(
                request(effort: .no, temperature: 0.4),
                protocolType: .deepSeek
            )
        )
        #expect(disabled["enable_thinking"] as? Bool == false)
        #expect((disabled["thinking"] as? [String: Any])?["type"] as? String == "disabled")
        #expect(disabled["reasoning_effort"] == nil)
        #expect(disabled["temperature"] as? Double == 0.4)
        #expect(disabled["max_tokens"] as? Int == 2_048)

        let maximum = try encodedObject(
            OpenAIChatCompletionRequestBody(
                request(effort: .max, temperature: 0.4),
                protocolType: .deepSeek
            )
        )
        #expect(maximum["enable_thinking"] == nil)
        #expect((maximum["thinking"] as? [String: Any])?["type"] as? String == "enabled")
        #expect(maximum["reasoning_effort"] as? String == "max")
        #expect(maximum["temperature"] == nil)
    }

    @Test("Responses and Anthropic clamp extended efforts to high")
    func extendedEffortMapping() throws {
        let responses = try encodedObject(OpenAIResponsesRequestBody(request(effort: .xhigh)))
        #expect((responses["reasoning"] as? [String: Any])?["effort"] as? String == "high")

        let responsesDisabled = try encodedObject(
            OpenAIResponsesRequestBody(request(effort: .no))
        )
        #expect(responsesDisabled["reasoning"] == nil)

        let anthropic = try encodedObject(AnthropicMessagesRequestBody(request(effort: .max)))
        #expect((anthropic["output_config"] as? [String: Any])?["effort"] as? String == "high")

        let anthropicDisabled = try encodedObject(
            AnthropicMessagesRequestBody(request(effort: .no, temperature: 0.4))
        )
        #expect(anthropicDisabled["thinking"] == nil)
        #expect(anthropicDisabled["output_config"] == nil)
        #expect(anthropicDisabled["temperature"] as? Double == 0.4)
    }

    private func request(
        effort: AgentReasoningEffort,
        temperature: Double? = nil
    ) -> AgentChatRequest {
        AgentChatRequest(
            runID: UUID(),
            model: "test-model",
            messages: [.user("Hello")],
            temperature: temperature,
            maxTokens: 2_048,
            reasoningEffort: effort
        )
    }

    private func encodedObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
