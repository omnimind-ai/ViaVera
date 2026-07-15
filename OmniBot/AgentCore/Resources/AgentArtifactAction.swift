import Foundation

nonisolated public struct AgentArtifactAction: Codable, Hashable, Sendable {
    public let type: String
    public let label: String
    public let target: String?
    public let payload: [String: AgentValue]

    public init(
        type: String,
        label: String,
        target: String? = nil,
        payload: [String: AgentValue] = [:]
    ) {
        self.type = type
        self.label = label
        self.target = target
        self.payload = payload
    }

    public var agentValue: AgentValue {
        .object([
            "type": .string(type),
            "label": .string(label),
            "target": target.map(AgentValue.string) ?? .null,
            "payload": .object(payload),
        ])
    }
}
