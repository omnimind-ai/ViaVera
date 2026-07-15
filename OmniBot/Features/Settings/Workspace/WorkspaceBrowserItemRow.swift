import SwiftUI

struct WorkspaceBrowserItemRow: View {
    let item: WorkspaceBrowserItem
    let isPreparingPreview: Bool
    let onOpenFile: (WorkspaceBrowserItem) -> Void
    let onOpenDirectory: ((WorkspaceBrowserPath) -> Void)?

    init(
        item: WorkspaceBrowserItem,
        isPreparingPreview: Bool,
        onOpenFile: @escaping (WorkspaceBrowserItem) -> Void,
        onOpenDirectory: ((WorkspaceBrowserPath) -> Void)? = nil
    ) {
        self.item = item
        self.isPreparingPreview = isPreparingPreview
        self.onOpenFile = onOpenFile
        self.onOpenDirectory = onOpenDirectory
    }

    var body: some View {
        switch item.kind {
        case .directory:
            if onOpenDirectory != nil {
                Button(action: openDirectory) {
                    WorkspaceBrowserRow(
                        item: item,
                        isPreparingPreview: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开文件夹")
            } else {
                NavigationLink(value: item.path) {
                    WorkspaceBrowserRow(
                        item: item,
                        isPreparingPreview: false
                    )
                }
                .accessibilityHint("打开文件夹")
            }
        case .file:
            Button(action: openFile) {
                WorkspaceBrowserRow(
                    item: item,
                    isPreparingPreview: isPreparingPreview
                )
            }
            .buttonStyle(.plain)
            .disabled(isPreparingPreview)
            .accessibilityHint("预览文件")
        case .symbolicLink, .other:
            WorkspaceBrowserRow(
                item: item,
                isPreparingPreview: false
            )
        }
    }

    private func openFile() {
        onOpenFile(item)
    }

    private func openDirectory() {
        onOpenDirectory?(item.path)
    }
}
