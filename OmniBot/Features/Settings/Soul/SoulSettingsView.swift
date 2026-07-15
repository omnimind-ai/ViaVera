import SwiftUI

struct SoulSettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var lastPersistedContent: String?

    var body: some View {
        @Bindable var settings = appModel.soulSettings

        SettingsPageLayout(title: "Soul") {
            Section {
                SettingsTextEditor(
                    prompt: "描述 Agent 的身份、语气、原则与边界",
                    text: $settings.content,
                    lineLimit: 12...20,
                    minimumHeight: 320
                )
            } header: {
                Text("系统提示")
            } footer: {
                Text("这里的内容会加入每次 Agent 运行的系统提示。")
            }

            if let errorMessage = settings.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .task {
            lastPersistedContent = settings.content
        }
        .task(id: settings.content) {
            await autoSave(settings.content)
        }
        .onDisappear(perform: savePendingChanges)
    }

    private func autoSave(_ content: String) async {
        guard let persistedContent = lastPersistedContent,
              content != persistedContent else {
            return
        }

        do {
            try await Task.sleep(for: AppDesign.settingsAutoSaveDelay)
        } catch {
            return
        }

        guard !Task.isCancelled,
              appModel.soulSettings.content == content else {
            return
        }

        await appModel.soulSettings.save(content)
        guard !Task.isCancelled,
              appModel.soulSettings.errorMessage == nil else {
            return
        }
        lastPersistedContent = appModel.soulSettings.content
    }

    private func savePendingChanges() {
        guard let persistedContent = lastPersistedContent else { return }
        let content = appModel.soulSettings.content
        guard content != persistedContent else { return }

        Task {
            await appModel.soulSettings.save(content)
        }
    }
}
