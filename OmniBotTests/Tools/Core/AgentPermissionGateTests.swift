import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent permission gate")
struct AgentPermissionGateTests {
    @Test("Disabled personal-data switches block every matching Agent tool family")
    func disabledPermissionsBlockTools() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let suiteName = "AgentPermissionGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AgentPermissionStore(defaults: defaults)
        let executor = makeToolExecutor(
            paths: temporary.paths,
            agentPermissionStore: store
        )
        let cases: [(toolName: String, permission: IOSPermissionKind)] = [
            ("healthkit_data_types", .healthKit),
            ("calendar_list", .calendars),
            ("contacts_search", .contacts),
            ("alarm_reminder_list", .alarms),
        ]

        for testCase in cases {
            let result = try await executeTool(
                testCase.toolName,
                arguments: titledArguments("Permission gate test"),
                using: executor,
                paths: temporary.paths
            )

            #expect(result.isError)
            #expect(result.metadata["code"] == .string("permission_disabled_in_app"))
            #expect(result.metadata["permission"] == .string(testCase.permission.rawValue))
            #expect(result.metadata["authorizationStatus"] == .string("disabled_in_app"))
            #expect(result.metadata["requiresUserInteraction"] == .bool(true))
        }
    }

    @Test("Enabling a switch lets the call pass the in-app permission gate")
    func enabledPermissionPassesGate() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let suiteName = "AgentPermissionGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AgentPermissionStore(defaults: defaults)
        await store.setEnabled(true, for: .healthKit)
        let executor = makeToolExecutor(
            paths: temporary.paths,
            agentPermissionStore: store
        )

        let result = try await executeTool(
            "healthkit_data_types",
            arguments: titledArguments("Enabled permission test"),
            using: executor,
            paths: temporary.paths
        )

        #expect(result.isError)
        #expect(result.metadata["code"] == .string("service_unavailable"))
        #expect(result.metadata["authorizationStatus"] == nil)
    }

    @Test("Tool names map to the intended personal permission")
    func toolPermissionMapping() {
        #expect(IOSPermissionKind.requiredPermission(
            forAgentToolName: "healthkit_workout_list"
        ) == .healthKit)
        #expect(IOSPermissionKind.requiredPermission(
            forAgentToolName: "calendar_event_create"
        ) == .calendars)
        #expect(IOSPermissionKind.requiredPermission(
            forAgentToolName: "contacts_delete"
        ) == .contacts)
        #expect(IOSPermissionKind.requiredPermission(
            forAgentToolName: "alarm_reminder_create"
        ) == .alarms)
        #expect(IOSPermissionKind.requiredPermission(
            forAgentToolName: "file_read"
        ) == nil)
    }
}
