import Foundation

nonisolated struct NativeToolScreen: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let components: [NativeToolComponent]
}
