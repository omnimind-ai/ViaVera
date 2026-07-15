import Foundation

nonisolated struct WorkspaceBrowserPath: Hashable, Sendable, Identifiable {
    static let root = WorkspaceBrowserPath(components: [])

    let components: [String]

    var id: String { shellPath }

    var shellPath: String {
        components.isEmpty
            ? "/workspace"
            : "/workspace/" + components.joined(separator: "/")
    }

    var title: String {
        components.last ?? "工作区"
    }

    var breadcrumbPaths: [WorkspaceBrowserPath] {
        [Self.root] + components.indices.map { index in
            WorkspaceBrowserPath(
                components: Array(components.prefix(index + 1))
            )
        }
    }
}
