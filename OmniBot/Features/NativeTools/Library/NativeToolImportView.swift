import SwiftUI

struct NativeToolImportView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let package: NativeToolPackage
    @State private var runtime: NativeToolRuntime?
    @State private var errorMessage: String?
    @State private var isInstalling = false

    var body: some View {
        NavigationStack {
            Group {
                if let runtime { NativeToolScreenView(runtime: runtime) }
                else { ProgressView() }
            }
            .navigationTitle("预览 · \(package.name)")
            .safeAreaInset(edge: .bottom) {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("添加到工具", action: install).disabled(isInstalling) }
            }
            .task {
                let record = NativeToolRecord(id: UUID(), revision: 0, package: package, previousPackage: nil, conversationID: nil, createdAt: .now, updatedAt: .now, isFavorite: false)
                runtime = NativeToolRuntime(document: NativeToolDocument(record: record, state: package.initialState, stateRevision: 0), store: appModel.nativeTools.store, isPreview: true)
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
#endif
    }

    private func install() {
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                let record = try await appModel.nativeTools.store.install(package)
                dismiss()
                appModel.openNativeTool(record.id)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
