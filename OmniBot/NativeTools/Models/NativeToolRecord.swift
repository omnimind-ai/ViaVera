import Foundation

nonisolated struct NativeToolRecord: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var revision: Int
    var package: NativeToolPackage
    var previousPackage: NativeToolPackage?
    var conversationID: UUID?
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var builtInID: String? = nil

    var url: URL { URL(string: "omnibot-tool://open/\(id.uuidString)")! }

    static func identifier(from url: URL) -> UUID? {
        guard url.scheme == "omnibot-tool", url.host == "open",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
