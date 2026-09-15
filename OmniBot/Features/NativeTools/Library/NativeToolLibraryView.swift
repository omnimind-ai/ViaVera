import SwiftUI
import UniformTypeIdentifiers

struct NativeToolLibraryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var search = ""
    @State private var isImporting = false
    @State private var importPackage: NativeToolImportRequest?
    @State private var deleting: NativeToolRecord?
    @State private var isConfirmingDelete = false

    var body: some View {
        @Bindable var library = appModel.nativeTools
        List {
            ForEach(filteredRecords) { record in
                NavigationLink(value: record.id) {
                    NativeToolLibraryRow(record: record)
                }
                .contextMenu {
                    Button(record.isFavorite ? "取消收藏" : "收藏", systemImage: record.isFavorite ? "star.slash" : "star") {
                        Task { await library.setFavorite(record) }
                    }
                    Button("删除", systemImage: "trash", role: .destructive) { requestDelete(record) }
                }
                .swipeActions {
                    Button("删除", systemImage: "trash", role: .destructive) { requestDelete(record) }
                }
            }
        }
        .overlay {
            if library.records.isEmpty {
                if library.isLoading {
                    ProgressView("正在读取工具…")
                } else {
                    ContentUnavailableView {
                        Label("让想法成为工具", systemImage: "square.grid.2x2")
                    } description: {
                        Text("告诉 AI 你需要什么，制作完成后在这里直接使用。")
                    } actions: {
                        Button("用 AI 制作", systemImage: "sparkles", action: create)
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else if filteredRecords.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .searchable(text: $search, prompt: "搜索工具")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("工具操作", systemImage: "ellipsis.circle") {
                    Button("导入工具包", systemImage: "square.and.arrow.down") { isImporting = true }
                    if library.hasMissingBuiltInTools {
                        Button("恢复内置工具", systemImage: "arrow.counterclockwise") {
                            Task { await library.restoreBuiltInTools() }
                        }
                    }
                }
                Button("用 AI 制作", systemImage: "plus", action: create)
            }
        }
        .sheet(item: $importPackage) { request in NativeToolImportView(package: request.package) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], onCompletion: importFile)
        .confirmationDialog("删除工具？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: deleteSelected)
        } message: {
            Text(deleting?.package.capabilities.contains("totp") == true
                ? "工具及验证码账户将被删除。请先在工具中导出加密备份。"
                : "工具及它保存的数据将被删除。")
        }
        .alert(item: $library.alert) { alert in
            Alert(title: Text("工具操作失败"), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .task { await library.load() }
        .onReceive(NotificationCenter.default.publisher(for: NativeToolStore.didChange)) { _ in
            Task { await library.load() }
        }
    }

    private var filteredRecords: [NativeToolRecord] {
        appModel.nativeTools.records.filter {
            search.isEmpty || $0.package.name.localizedStandardContains(search)
                || ($0.package.summary?.localizedStandardContains(search) ?? false)
        }
    }

    private func create() {
        do { try appModel.beginNativeToolConversation() }
        catch { appModel.nativeTools.alert = NativeToolAlert(error.localizedDescription) }
    }

    private func requestDelete(_ record: NativeToolRecord) {
        deleting = record
        isConfirmingDelete = true
    }

    private func deleteSelected() {
        guard let deleting else { return }
        Task { await appModel.nativeTools.delete(deleting) }
        self.deleting = nil
    }

    private func importFile(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size <= NativeToolValidator.maximumPackageBytes else { throw NativeToolError("请选择不超过 256 KB 的 JSON 工具包。") }
            importPackage = NativeToolImportRequest(package: try NativeToolValidator.decode(Data(contentsOf: url)))
        } catch { appModel.nativeTools.alert = NativeToolAlert(error.localizedDescription) }
    }
}
