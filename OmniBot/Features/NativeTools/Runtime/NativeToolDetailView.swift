import SwiftUI
import UniformTypeIdentifiers

struct NativeToolDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    let toolID: UUID
    @State private var runtime: NativeToolRuntime?
    @State private var host: NativeToolHostCapabilities?
    @State private var alert: NativeToolAlert?
    @State private var isExporting = false
    @State private var exportDocument: NativeToolJSONDocument?
    @State private var isRollingBack = false
    @State private var isConfirmingReload = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if let runtime { NativeToolScreenView(runtime: runtime) }
            else if let loadError {
                ContentUnavailableView {
                    Label("无法打开工具", systemImage: "exclamationmark.triangle")
                } description: { Text(loadError) } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else { ProgressView("正在打开工具…") }
        }
        .navigationTitle(runtime?.record.package.name ?? "工具")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("工具操作", systemImage: "ellipsis.circle") {
                    Button("让 AI 修改", systemImage: "sparkles", action: edit)
                    Button("导出工具包", systemImage: "square.and.arrow.up", action: export)
                    Button("重新载入", systemImage: "arrow.clockwise", action: requestReload)
                    if runtime?.record.previousPackage != nil {
                        Button("恢复上一版本", systemImage: "clock.arrow.circlepath") { isRollingBack = true }
                    }
                }
                .disabled(runtime == nil)
            }
        }
        .confirmationDialog("恢复上一版本？", isPresented: $isRollingBack, titleVisibility: .visible) {
            Button("恢复", action: rollback)
        } message: { Text("恢复工具的界面与逻辑，保留当前数据。") }
        .confirmationDialog("放弃未保存的更改？", isPresented: $isConfirmingReload, titleVisibility: .visible) {
            Button("重新载入", role: .destructive) { Task { await load(force: true) } }
        } message: { Text("将载入已保存的数据，当前未保存的修改会被丢弃。") }
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: .json, defaultFilename: "native-tool.json") { result in
            if case let .failure(error) = result { alert = NativeToolAlert(error.localizedDescription) }
        }
        .alert(item: $alert) { alert in
            Alert(title: Text("工具操作失败"), message: Text(alert.message), dismissButton: .default(Text("好")))
        }
        .task(id: toolID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NativeToolStore.didChange)) { _ in
            Task { await load() }
        }
        .background {
            if let host { NativeToolCapabilityPresentation(host: host) }
        }
        .onDisappear { runtime?.suspend() }
        .onChange(of: host?.isCredentialSessionUnlocked) { previous, current in
            if previous == true, current == false { runtime?.suspend() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && host?.isAuthorizing != true) { runtime?.suspend() }
        }
    }

    private func load(force: Bool = false) async {
        if let runtime {
            await runtime.flush()
            if runtime.persistenceFailed, !force { return }
        }
        do {
            let document = try await appModel.nativeTools.store.load(toolID)
            if !force, runtime?.record.revision == document.record.revision { return }
            runtime?.suspend()
            let host = NativeToolHostCapabilities(toolID: toolID, permissions: document.record.package.capabilities)
            self.host = host
            runtime = NativeToolRuntime(document: document, store: appModel.nativeTools.store, host: host)
            loadError = nil
        } catch {
            if runtime == nil { loadError = error.localizedDescription }
            else { alert = NativeToolAlert(error.localizedDescription) }
        }
    }

    private func export() {
        guard let runtime else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportDocument = NativeToolJSONDocument(data: try encoder.encode(runtime.record.package))
            isExporting = true
        } catch { alert = NativeToolAlert(error.localizedDescription) }
    }

    private func edit() {
        do { try appModel.beginNativeToolConversation(editing: toolID) }
        catch { alert = NativeToolAlert(error.localizedDescription) }
    }

    private func requestReload() {
        if runtime?.persistenceFailed == true { isConfirmingReload = true }
        else { Task { await load(force: true) } }
    }

    private func rollback() {
        guard let runtime else { return }
        Task {
            await runtime.flush()
            guard !runtime.persistenceFailed else { return }
            do {
                try await appModel.nativeTools.store.rollback(toolID, expectedRevision: runtime.record.revision)
                await load(force: true)
            } catch { alert = NativeToolAlert(error.localizedDescription) }
        }
    }
}
