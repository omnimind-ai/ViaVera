import Foundation

nonisolated public struct AgentToolExecutionResult: Codable, Hashable, Sendable {
    public let content: String
    public let isError: Bool
    public let metadata: [String: AgentValue]
    public let artifacts: [AgentArtifact]
    public let workspaceID: String?
    public let actions: [AgentArtifactAction]

    public init(
        content: String,
        isError: Bool = false,
        metadata: [String: AgentValue] = [:],
        artifacts: [AgentArtifact] = [],
        workspaceID: String? = nil,
        actions: [AgentArtifactAction] = []
    ) {
        self.content = content
        self.isError = isError
        self.metadata = metadata
        self.artifacts = artifacts
        self.workspaceID = workspaceID
        self.actions = actions
    }

    public func modelContent(using encoder: JSONEncoder = JSONEncoder()) throws -> String {
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var object: [String: AgentValue] = [
            "success": .bool(!isError),
            "status": .string(isError ? "error" : "completed"),
            "summary": .string(content),
            "content": .string(content),
            "metadata": .object(metadata),
        ]
        for key in [
            "toolName",
            "displayName",
            "toolTitle",
            "toolType",
            "status",
            "previewJson",
            "rawResultJson",
        ] where key != "summary" {
            if let value = metadata[key] { object[key] = value }
        }
        if !artifacts.isEmpty {
            object["artifacts"] = .array(artifacts.map(\.agentValue))
        }
        if let workspaceID {
            object["workspaceId"] = .string(workspaceID)
        }
        if !actions.isEmpty {
            object["actions"] = .array(actions.map(\.agentValue))
        }
        let value = AgentValue.object(object)
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
