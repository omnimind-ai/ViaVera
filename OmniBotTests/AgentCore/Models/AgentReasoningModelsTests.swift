import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent reasoning models")
struct AgentReasoningModelsTests {
    @Test("Legacy assistant JSON decodes without reasoning fields")
    func legacyAssistantDecoding() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "role": "assistant",
              "content": "Legacy answer",
              "toolCalls": []
            }
            """.utf8
        )

        let message = try JSONDecoder().decode(AgentMessage.self, from: data)

        #expect(message.id == id)
        #expect(message.content == "Legacy answer")
        #expect(message.reasoningContent == nil)
        #expect(message.providerMetadata == nil)
    }

    @Test("Assistant reasoning survives a Codable round trip")
    func reasoningRoundTrip() throws {
        let message = AgentMessage.assistant(
            "Final answer",
            reasoningContent: "Compare the alternatives first."
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)

        #expect(decoded == message)
        #expect(decoded.reasoningContent == "Compare the alternatives first.")
    }

    @Test("Persisted reasoning is bounded to 16 KiB of characters")
    func boundedReasoningPersistence() {
        let limit = AgentReasoningContent.maximumPersistedCharacters
        let original = String(repeating: "r", count: limit + 257)

        let bounded = AgentMessage.assistant(
            reasoningContent: original
        ).boundedReasoningForPersistence()
        let reasoning = bounded.reasoningContent

        #expect(reasoning?.count == limit)
        #expect(reasoning?.hasPrefix(AgentReasoningContent.truncationNotice) == true)
        #expect(
            reasoning?.hasSuffix(
                String(original.suffix(limit - AgentReasoningContent.truncationNotice.count))
            ) == true
        )
    }

    @Test("Reasoning at the persistence limit remains unchanged")
    func reasoningAtLimitIsUnchanged() {
        let original = String(
            repeating: "思",
            count: AgentReasoningContent.maximumPersistedCharacters
        )

        let bounded = AgentMessage.assistant(
            reasoningContent: original
        ).boundedReasoningForPersistence()

        #expect(bounded.reasoningContent == original)
    }

    @Test("Continuation metadata within the tool-turn budget remains persisted")
    func continuationMetadataWithinBudgetIsRetained() {
        let metadata = AgentValue.object([
            "opaque": .string(String(repeating: "m", count: 80 * 1_024)),
        ])

        let bounded = AgentMessage.assistant(
            providerMetadata: metadata,
            toolCalls: [AgentToolCall(id: "call", name: "tool", arguments: "{}")]
        ).boundedReasoningForPersistence()

        #expect(bounded.providerMetadata == metadata)
    }

    @Test("Oversized continuation metadata is still discarded")
    func oversizedContinuationMetadataIsDiscarded() {
        let metadata = AgentValue.object([
            "opaque": .string(
                String(
                    repeating: "m",
                    count: AgentMessage.maximumPersistedProviderMetadataBytes + 1_024
                )
            ),
        ])

        let bounded = AgentMessage.assistant(
            providerMetadata: metadata
        ).boundedReasoningForPersistence()

        #expect(bounded.providerMetadata == nil)
    }
}
