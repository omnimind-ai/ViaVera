import Foundation

nonisolated struct WorkspaceBrowserItem: Hashable, Sendable, Identifiable {
    let path: WorkspaceBrowserPath
    let kind: WorkspaceBrowserItemKind
    let byteCount: Int64
    let modifiedAt: Date

    var id: WorkspaceBrowserPath { path }
    var name: String { path.components.last ?? path.shellPath }
    var pathExtension: String { URL(filePath: name).pathExtension.lowercased() }
}
