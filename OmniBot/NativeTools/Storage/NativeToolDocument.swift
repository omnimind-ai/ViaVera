import Foundation

nonisolated struct NativeToolDocument: Codable, Sendable {
    var record: NativeToolRecord
    var state: [String: AgentValue]
    var stateRevision: Int
}
