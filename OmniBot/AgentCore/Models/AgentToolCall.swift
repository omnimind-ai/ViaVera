import Foundation

nonisolated public struct AgentToolCall: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// OpenAI-compatible APIs encode function arguments as a JSON string.
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public func decodedArguments(using decoder: JSONDecoder = JSONDecoder()) throws -> AgentValue {
        try decoder.decode(AgentValue.self, from: Data(arguments.utf8))
    }
}
