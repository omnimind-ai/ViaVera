import SwiftUI

struct MemorySettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var lastPersistedContent: String?

    var body: some View {
        @Bindable var settings = appModel.memorySettings

        SettingsPageLayout(title: "Memory") {
            Section {
                SettingsTextEditor(
                    prompt: "输入需要长期保留的事实、偏好或工作约定",
                    text: $settings.longTermMemory,
                    lineLimit: 9...16,
                    minimumHeight: 240
                )
            } header: {
                Text("长期记忆")
            } footer: {
                Text("长期记忆会在不同会话之间持续生效。")
            }

            Section("今日记忆") {
                if trimmedTodayMemory.isEmpty {
                    ContentUnavailableView {
                        Label("今天还没有记忆", systemImage: "calendar")
                    } description: {
                        Text("Agent 产生的每日记忆会显示在这里。")
                    }
                    .frame(minHeight: 96)
                } else {
                    SettingsCodeBlockView(
                        text: settings.todayMemory,
                        minimumHeight: 150
                    )
                }
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
            lastPersistedContent = settings.longTermMemory
        }
        .task(id: settings.longTermMemory) {
            await autoSave(settings.longTermMemory)
        }
        .onDisappear(perform: savePendingChanges)
    }

    private var trimmedTodayMemory: String {
        appModel.memorySettings.todayMemory.trimmingCharacters(in: .whitespacesAndNewlines)
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
              appModel.memorySettings.longTermMemory == content else {
            return
        }

        await appModel.memorySettings.save(content)
        guard !Task.isCancelled,
              appModel.memorySettings.errorMessage == nil else {
            return
        }
        lastPersistedContent = appModel.memorySettings.longTermMemory
    }

    private func savePendingChanges() {
        guard let persistedContent = lastPersistedContent else { return }
        let content = appModel.memorySettings.longTermMemory
        guard content != persistedContent else { return }

        Task {
            await appModel.memorySettings.save(content)
        }
    }
}
