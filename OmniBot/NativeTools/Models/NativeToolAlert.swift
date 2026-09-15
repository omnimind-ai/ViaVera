import Foundation

nonisolated struct NativeToolAlert: Identifiable {
    let id = UUID()
    let message: String

    init(_ message: String) { self.message = message }
}
