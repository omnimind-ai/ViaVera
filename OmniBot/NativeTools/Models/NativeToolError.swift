import Foundation

nonisolated struct NativeToolError: LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) { self.message = message }
}
