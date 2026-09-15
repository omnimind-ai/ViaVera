import Foundation

nonisolated struct NativeToolAction: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case set, append, remove, toggleItem, navigate, setSession, invoke
    }

    let type: Kind
    var key: String? = nil
    var value: AgentValue? = nil
    var field: String? = nil
    var screen: String? = nil
    var when: AgentValue? = nil
    var operation: String? = nil
    var arguments: [String: AgentValue]? = nil
    var result: String? = nil
}
