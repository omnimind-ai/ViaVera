import Foundation

@MainActor
protocol NativeToolHostCalling: AnyObject {
    var sessionID: UUID { get }
    func invoke(_ operation: String, arguments: [String: AgentValue]) async throws -> AgentValue
    func suspend()
}
