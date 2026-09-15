import Foundation

nonisolated extension OmniAgentToolDefinitions {
    static let nativeToolList = nativeDefinition(
        "native_tool_list", "List the user's installed native tools (metadata only; no user data or credentials).", properties: [:], required: []
    )
    static let nativeToolRead = nativeDefinition(
        "native_tool_read", "Read an installed native tool's source package and revision for editing. Does not return runtime data or secrets.",
        properties: ["tool_id": nativeString("Tool UUID returned by native_tool_list.")], required: ["tool_id"]
    )
    static let nativeToolValidate = nativeDefinition(
        "native_tool_validate", "Validate a workspace JSON package for SwiftUI native tools. Read the native-tool-builder skill before authoring packages.",
        properties: ["path": nativeString("Workspace path to the JSON package.")], required: ["path"]
    )
    static let nativeToolInstall = nativeDefinition(
        "native_tool_install", "Install a validated native tool or update its existing UUID while preserving user data. Returns an in-app open link. Updating requires the current expected_revision from native_tool_read.",
        properties: [
            "path": nativeString("Workspace path to the JSON package."),
            "tool_id": nativeString("Existing UUID for an update; omit when creating a new tool."),
            "expected_revision": .object([
                "type": .string("integer"), "minimum": .number(1), "maximum": .number(1_000_000),
                "description": .string("Current revision, required for updates."),
            ]),
        ], required: ["path"]
    )

    private static func nativeString(_ description: String) -> AgentValue {
        .object(["type": .string("string"), "description": .string(description), "maxLength": .number(4096)])
    }

    private static func nativeDefinition(
        _ name: String, _ description: String, properties: [String: AgentValue], required: [String]
    ) -> AgentToolDefinition {
        var properties = properties
        properties["tool_title"] = .object([
            "type": .string("string"), "description": .string("Short user-visible action title."),
            "minLength": .number(1), "maxLength": .number(160),
        ])
        return AgentToolDefinition(name: name, description: description, parameters: .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array((["tool_title"] + required).map(AgentValue.string)),
            "additionalProperties": .bool(false),
        ]))
    }
}
