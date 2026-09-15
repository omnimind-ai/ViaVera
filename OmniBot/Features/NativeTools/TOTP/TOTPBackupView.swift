import SwiftUI
import UniformTypeIdentifiers

struct TOTPBackupView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TOTPManagerModel
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var document: NativeToolJSONDocument?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("备份密码", text: $password)
                    SecureField("再次输入密码（导出时）", text: $confirmation)
                } footer: {
                    Text("导出时使用至少 12 个字符的独立密码。恢复需要同一密码，OmniBot 无法找回。")
                }
                Section {
                    Button("导出加密备份", systemImage: "square.and.arrow.up", action: export)
                        .disabled(password.count < 12 || password != confirmation || isWorking)
                    Button("从加密备份恢复", systemImage: "square.and.arrow.down") { isImporting = true }
                        .disabled(password.isEmpty || isWorking)
                }
                if isWorking { ProgressView("正在处理…") }
                if let message { Text(message) }
            }
            .navigationTitle("备份与恢复")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .fileExporter(isPresented: $isExporting, document: document, contentType: .json, defaultFilename: "totp-encrypted-backup.json") { result in
                document = nil
                if case let .failure(error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], onCompletion: restore)
            .onDisappear { password = ""; confirmation = ""; document = nil }
        }
#if os(macOS)
        .frame(minWidth: 460, minHeight: 350)
#endif
    }

    private func export() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let data = try await model.export(password: password)
                guard model.isUnlocked else { return }
                document = NativeToolJSONDocument(data: data)
                isExporting = true
            } catch { message = error.localizedDescription }
        }
    }

    private func restore(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 512 * 1024 else {
                throw NativeToolError("备份文件不能超过 512 KB。")
            }
            let data = try Data(contentsOf: url)
            isWorking = true
            Task {
                defer { isWorking = false }
                do { try await model.restore(data, password: password); message = "已恢复账户，重复账户已跳过。" }
                catch { message = error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
}
