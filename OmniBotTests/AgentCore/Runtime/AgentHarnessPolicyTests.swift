import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent harness policies")
struct AgentHarnessPolicyTests {
    @Test("Chat compaction preserves conversation context without task instructions")
    func chatCompactionProfile() {
        let user = AgentMessage.user("I want to talk about my plans.")
        let messages = ConversationContextCompaction.requestMessages(
            existingSummary: "The user enjoys painting.", messagesToCompact: [user], mode: .chat
        )
        #expect(messages.first?.role == .system)
        #expect(messages.first?.content?.contains("chat companion") == true)
        #expect(messages.first?.content?.contains("Commands executed") == false)
        #expect(messages.contains(user))
        #expect(messages.contains { $0.content?.contains("enjoys painting") == true })
    }

    @Test("Adaptive compaction reserve scales across model context sizes")
    func adaptiveCompactionTrigger() {
        #expect(AgentAutoCompactionPolicy.trigger(contextCapacity: 128_000) == 112_000)
        #expect(AgentAutoCompactionPolicy.trigger(contextCapacity: 32_000) == 28_000)
        #expect(AgentAutoCompactionPolicy.trigger(contextCapacity: 8_000) == 5_952)
        #expect(AgentAutoCompactionPolicy.effectiveCapacity(
            configuredContextWindow: 128_000,
            observedContextWindow: 64_000
        ) == 64_000)
    }

    @Test("Context overflow detection is provider-specific and excludes rate limits")
    func contextOverflowClassification() {
        let overflow = OpenAICompatibleClientError.httpError(
            statusCode: 400,
            message: "maximum context length exceeded",
            type: "invalid_request_error",
            code: "context_length_exceeded",
            body: nil
        )
        let rateLimit = OpenAICompatibleClientError.httpError(
            statusCode: 429,
            message: "Too many tokens per minute due to rate limit",
            type: "rate_limit_error",
            code: nil,
            body: nil
        )

        #expect(AgentContextOverflowDetector.isContextOverflow(overflow))
        #expect(!AgentContextOverflowDetector.isContextOverflow(rateLimit))
        #expect(!AgentContextOverflowDetector.isContextOverflow(CancellationError()))
    }
}
