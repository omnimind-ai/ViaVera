import Foundation

/// A declarative document, never executable Swift, JavaScript, or HTML.
nonisolated struct NativeToolPackage: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let name: String
    let summary: String?
    let symbol: String?
    let stateVersion: Int
    let initialState: [String: AgentValue]
    let screens: [NativeToolScreen]
    let actions: [String: [NativeToolAction]]
    let capabilities: [String]
    var sessionState: [String: AgentValue]? = nil
    var onRefresh: String? = nil
}
