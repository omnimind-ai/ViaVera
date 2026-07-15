import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceBrowserModel {
    private(set) var itemsByPath: [WorkspaceBrowserPath: [WorkspaceBrowserItem]] = [:]
    private(set) var loadingPaths: Set<WorkspaceBrowserPath> = []
    private(set) var errorMessagesByPath: [WorkspaceBrowserPath: String] = [:]

    private let store: WorkspaceBrowserStore

    init(paths: WorkspacePaths) {
        store = WorkspaceBrowserStore(paths: paths)
    }

    init(store: WorkspaceBrowserStore) {
        self.store = store
    }

    func items(in path: WorkspaceBrowserPath) -> [WorkspaceBrowserItem]? {
        itemsByPath[path]
    }

    func isLoading(_ path: WorkspaceBrowserPath) -> Bool {
        loadingPaths.contains(path)
    }

    func errorMessage(in path: WorkspaceBrowserPath) -> String? {
        errorMessagesByPath[path]
    }

    func load(_ path: WorkspaceBrowserPath, force: Bool = false) async {
        guard !loadingPaths.contains(path) else { return }
        guard force || itemsByPath[path] == nil else { return }

        loadingPaths.insert(path)
        defer { loadingPaths.remove(path) }

        let store = store
        do {
            let items = try await Task.detached(priority: .userInitiated) {
                try store.items(in: path)
            }.value
            itemsByPath[path] = items
            errorMessagesByPath[path] = nil
        } catch {
            errorMessagesByPath[path] = error.localizedDescription
        }
    }

    func makePreviewSnapshot(for item: WorkspaceBrowserItem) async throws -> URL {
        let store = store
        return try await Task.detached(priority: .userInitiated) {
            try store.makePreviewSnapshot(for: item)
        }.value
    }

    func removePreviewSnapshot(_ snapshotURL: URL) {
        let store = store
        Task.detached(priority: .utility) {
            store.removePreviewSnapshot(snapshotURL)
        }
    }
}
