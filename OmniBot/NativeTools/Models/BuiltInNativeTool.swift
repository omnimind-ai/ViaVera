import Foundation

nonisolated struct BuiltInNativeTool: Sendable {
    /// Stable catalog identity; each installation gets its own tool UUID and data.
    let id: String
    let package: NativeToolPackage
}
