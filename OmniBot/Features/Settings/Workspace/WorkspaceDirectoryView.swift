import QuickLook
import SwiftUI

struct WorkspaceDirectoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var previewedFileURL: URL?
    @State private var previewRequestID: UUID?
    @State private var previewingPath: WorkspaceBrowserPath?
    @State private var previewErrorMessage = ""
    @State private var isShowingPreviewError = false

    let path: WorkspaceBrowserPath
    let onSelectBreadcrumbPath: (WorkspaceBrowserPath) -> Void
    let onOpenDirectory: ((WorkspaceBrowserPath) -> Void)?

    init(
        path: WorkspaceBrowserPath,
        onSelectBreadcrumbPath: @escaping (WorkspaceBrowserPath) -> Void = { _ in },
        onOpenDirectory: ((WorkspaceBrowserPath) -> Void)? = nil
    ) {
        self.path = path
        self.onSelectBreadcrumbPath = onSelectBreadcrumbPath
        self.onOpenDirectory = onOpenDirectory
    }

    var body: some View {
        let browser = appModel.workspaceBrowser
        let items = browser.items(in: path)
        let isLoading = browser.isLoading(path)

        SettingsPageLayout(
            title: path.title,
            actions: {
                Button("刷新", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(isLoading)
            }
        ) {
            Section {
                WorkspaceBreadcrumbView(
                    path: path,
                    onSelectPath: onSelectBreadcrumbPath
                )
            }

            Section {
                if let items, !items.isEmpty {
                    ForEach(items) { item in
                        WorkspaceBrowserItemRow(
                            item: item,
                            isPreparingPreview: previewingPath == item.path,
                            onOpenFile: beginPreview,
                            onOpenDirectory: onOpenDirectory
                        )
                    }
                } else if isLoading {
                    ProgressView("正在读取文件夹…")
                        .frame(maxWidth: .infinity, minHeight: 96)
                } else if let errorMessage = browser.errorMessage(in: path) {
                    ContentUnavailableView {
                        Label("无法读取文件夹", systemImage: "exclamationmark.folder")
                    } description: {
                        Text(errorMessage)
                            .textSelection(.enabled)
                    } actions: {
                        Button("重试", action: refresh)
                    }
                    .frame(minHeight: 120)
                } else {
                    ContentUnavailableView {
                        Label("文件夹为空", systemImage: "folder")
                    }
                    .frame(minHeight: 120)
                }
            }

            if items != nil, let errorMessage = browser.errorMessage(in: path) {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .task(id: path) {
            await browser.load(path, force: true)
        }
        .refreshable {
            await browser.load(path, force: true)
        }
        .quickLookPreview($previewedFileURL)
        .onChange(of: previewedFileURL) { oldValue, newValue in
            guard oldValue != newValue, let oldValue else { return }
            browser.removePreviewSnapshot(oldValue)
        }
        .onDisappear(perform: cancelPreview)
        .alert("无法预览文件", isPresented: $isShowingPreviewError) {
        } message: {
            Text(previewErrorMessage)
        }
    }

    private func refresh() {
        Task {
            await appModel.workspaceBrowser.load(path, force: true)
        }
    }

    private func beginPreview(_ item: WorkspaceBrowserItem) {
        let requestID = UUID()
        previewRequestID = requestID
        previewingPath = item.path
        previewedFileURL = nil

        Task {
            do {
                let snapshotURL = try await appModel.workspaceBrowser.makePreviewSnapshot(
                    for: item
                )
                guard previewRequestID == requestID else {
                    appModel.workspaceBrowser.removePreviewSnapshot(snapshotURL)
                    return
                }
                previewedFileURL = snapshotURL
            } catch {
                guard previewRequestID == requestID else { return }
                previewErrorMessage = error.localizedDescription
                isShowingPreviewError = true
            }

            if previewRequestID == requestID {
                previewRequestID = nil
                previewingPath = nil
            }
        }
    }

    private func cancelPreview() {
        previewRequestID = nil
        previewingPath = nil
        previewedFileURL = nil
    }
}
