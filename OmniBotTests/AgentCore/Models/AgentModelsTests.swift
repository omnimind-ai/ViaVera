import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent wire models")
struct AgentModelsTests {
    @Test("Assistant tool calls and role=tool results survive persistence encoding")
    func toolMessagesRoundTrip() throws {
        let call = AgentToolCall(
            id: "call_1",
            name: "terminal_execute",
            arguments: #"{"command":"pwd"}"#
        )
        let messages = [
            AgentMessage.assistant(toolCalls: [call]),
            AgentMessage.tool(
                callID: call.id,
                name: call.name,
                content: #"{"success":true,"content":"/workspace"}"#
            ),
        ]

        let data = try JSONEncoder().encode(messages)
        let decoded = try JSONDecoder().decode([AgentMessage].self, from: data)

        #expect(decoded == messages)
        #expect(decoded[0].toolCalls.first == call)
        #expect(decoded[1].role == .tool)
        #expect(decoded[1].toolCallID == call.id)
    }

    @Test("Tool JSON schema retains nested values")
    func agentValueRoundTrip() throws {
        let schema = AgentValue.object([
            "type": .string("object"),
            "required": .array([.string("command")]),
            "properties": .object([
                "command": .object(["type": .string("string")]),
                "timeout": .object(["type": .string("number")]),
            ]),
        ])

        let data = try JSONEncoder().encode(schema)
        #expect(try JSONDecoder().decode(AgentValue.self, from: data) == schema)
    }

    @Test("Token usage addition saturates instead of overflowing")
    func usageAdditionSaturates() {
        let maximum = AgentUsage(
            promptTokens: .max,
            completionTokens: .max,
            totalTokens: .max
        )
        let sum = maximum + AgentUsage(
            promptTokens: 1,
            completionTokens: 1,
            totalTokens: 1
        )

        #expect(sum.promptTokens == .max)
        #expect(sum.completionTokens == .max)
        #expect(sum.totalTokens == .max)
    }

    @Test("Legacy token usage decodes with zero cached tokens")
    func legacyUsageDecoding() throws {
        let data = Data(
            #"{"promptTokens":10,"completionTokens":4,"totalTokens":14}"#.utf8
        )

        let usage = try JSONDecoder().decode(AgentUsage.self, from: data)

        #expect(usage.cachedTokens == 0)
        #expect(usage.cacheCreationTokens == 0)
        #expect(!usage.reportsCacheUsage)
    }
}
