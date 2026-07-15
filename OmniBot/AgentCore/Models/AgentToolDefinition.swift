import Foundation

nonisolated public struct AgentToolDefinition: Codable, Hashable, Sendable {
    public let name: String
    public let description: String
    public let parameters: AgentValue

    public init(name: String, description: String, parameters: AgentValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}
