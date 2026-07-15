import Foundation

nonisolated struct WorkspaceBrowserStore: Sendable {
    private let paths: WorkspacePaths
    private let fileSystem: WorkspaceDescriptorFileSystem
    private let resourceProtocol: AgentResourceProtocol

    init(paths: WorkspacePaths) {
        self.paths = paths
        fileSystem = WorkspaceDescriptorFileSystem(paths: paths)
        resourceProtocol = AgentResourceProtocol(paths: paths)
    }

    func items(in directory: WorkspaceBrowserPath) throws -> [WorkspaceBrowserItem] {
        let directoryPath = try fileSystem.parse(directory.shellPath)
        let metadata = try fileSystem.metadata(for: directoryPath)
        guard metadata.kind == .directory else {
            throw OmniAgentToolError("Path '\(directory.shellPath)' is not a directory.")
        }

        let result = try fileSystem.list(
            directoryPath,
            recursive: false,
            maximumEntries: Int.max - 1
        )
        return result.entries
            .map(makeItem)
            .sorted(by: areInDisplayOrder)
    }

    func makePreviewSnapshot(for item: WorkspaceBrowserItem) throws -> URL {
        guard item.kind == .file else {
            throw OmniAgentToolError("Path '\(item.path.shellPath)' is not a regular file.")
        }

        let workspaceURL = item.path.components.reduce(paths.root) { partial, component in
            partial.appending(path: component)
        }
        let resourceIdentifier = try resourceProtocol.resourceURI(for: workspaceURL)
        guard let resourceURL = URL(string: resourceIdentifier) else {
            throw AgentResourceError.invalidResourceURL(resourceIdentifier)
        }
        return try resourceProtocol.makeQuickLookSnapshot(for: resourceURL)
    }

    func removePreviewSnapshot(_ snapshotURL: URL) {
        resourceProtocol.removeQuickLookSnapshot(snapshotURL)
    }

    private func makeItem(
        from entry: WorkspaceDescriptorFileSystem.DirectoryEntry
    ) -> WorkspaceBrowserItem {
        WorkspaceBrowserItem(
            path: WorkspaceBrowserPath(components: entry.path.components),
            kind: itemKind(for: entry.metadata.kind),
            byteCount: entry.metadata.size,
            modifiedAt: entry.metadata.modifiedAt
        )
    }

    private func itemKind(
        for kind: WorkspaceDescriptorFileSystem.ItemKind
    ) -> WorkspaceBrowserItemKind {
        switch kind {
        case .directory:
            .directory
        case .regular:
            .file
        case .symbolicLink:
            .symbolicLink
        case .other:
            .other
        }
    }

    private func areInDisplayOrder(
        _ lhs: WorkspaceBrowserItem,
        _ rhs: WorkspaceBrowserItem
    ) -> Bool {
        let lhsRank = displayRank(for: lhs.kind)
        let rhsRank = displayRank(for: rhs.kind)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func displayRank(for kind: WorkspaceBrowserItemKind) -> Int {
        switch kind {
        case .directory: 0
        case .file: 1
        case .symbolicLink: 2
        case .other: 3
        }
    }
}
