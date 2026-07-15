import SwiftUI

struct WorkspaceBrowserView: View {
    @State private var macOSPath = WorkspaceBrowserPath.root

    let onSelectBreadcrumbPath: (WorkspaceBrowserPath, WorkspaceBrowserPath) -> Void

    init(
        onSelectBreadcrumbPath: @escaping (
            WorkspaceBrowserPath,
            WorkspaceBrowserPath
        ) -> Void = { _, _ in }
    ) {
        self.onSelectBreadcrumbPath = onSelectBreadcrumbPath
    }

    var body: some View {
#if os(macOS)
        WorkspaceDirectoryView(
            path: macOSPath,
            onSelectBreadcrumbPath: selectMacOSPath,
            onOpenDirectory: selectMacOSPath
        )
#else
        WorkspaceDirectoryView(path: .root)
            .navigationDestination(for: WorkspaceBrowserPath.self) { path in
                WorkspaceDirectoryView(
                    path: path,
                    onSelectBreadcrumbPath: { targetPath in
                        onSelectBreadcrumbPath(targetPath, path)
                    }
                )
            }
#endif
    }

    private func selectMacOSPath(_ path: WorkspaceBrowserPath) {
        macOSPath = path
    }
}
