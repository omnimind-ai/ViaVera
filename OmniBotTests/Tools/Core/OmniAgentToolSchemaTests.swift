import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent tool schemas")
struct OmniAgentToolSchemaTests {
    @Test("Every advertised tool requires a visible tool title")
    func everySchemaRequiresToolTitle() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        let definitions = await executor.availableTools()
#if os(macOS)
        let names = Set(definitions.map(\.name))
        #expect(definitions.count == 35)
        #expect(names.contains("healthkit_data_types"))
        #expect(names.contains("calendar_list"))
        #expect(names.contains("contacts_search"))
        #expect(!names.contains(where: { $0.hasPrefix("alarm_reminder_") }))
#else
        #expect(definitions.count == 38)
#endif
        #expect(definitions.contains(where: { $0.name == "context_time_now" }))
        #expect(Set(definitions.map(\AgentToolDefinition.name)).count == definitions.count)

        for definition in definitions {
            let parameters = try #require(definition.parameters.objectValue)
            let properties = try #require(parameters["properties"]?.objectValue)
            let requiredValue = try #require(parameters["required"])
            guard case let .array(required) = requiredValue else {
                Issue.record("\(definition.name) has no required array")
                continue
            }

            #expect(properties["tool_title"] != nil, "\(definition.name) must define tool_title")
            #expect(required.contains(.string("tool_title")), "\(definition.name) must require tool_title")
            #expect(parameters["additionalProperties"] == .bool(false))
        }
    }

    @Test("Exact-time tool returns local and UTC timestamps")
    func exactTimeTool() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        let result = try await executeTool(
            "context_time_now",
            arguments: titledArguments("Check exact time"),
            using: executor,
            paths: temporary.paths
        )

        #expect(!result.isError)
        #expect(result.content.contains("Local:"))
        #expect(result.content.contains("UTC:"))
        #expect(result.metadata["timeZone"] != nil)
    }

    @Test("Execution rejects a missing tool title")
    func missingToolTitleIsRejected() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        let result = try await executeTool(
            "file_list",
            arguments: [:],
            using: executor,
            paths: temporary.paths
        )

        #expect(result.isError)
        #expect(result.content.contains("tool_title"))
    }

    @Test("Execution rejects rather than truncates a long tool title")
    func longToolTitleIsRejected() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        let result = try await executeTool(
            "file_list",
            arguments: titledArguments(String(repeating: "T", count: 161)),
            using: executor,
            paths: temporary.paths
        )

        #expect(result.isError)
        #expect(result.content.contains("160-character limit"))
        #expect(result.metadata["toolTitle"] == nil)
    }
}
