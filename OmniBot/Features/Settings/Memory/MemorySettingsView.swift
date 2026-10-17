import SwiftUI

struct MemorySettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.memorySettings

        SettingsPageLayout(title: "Memory") {
            Section {
                SettingsTextEditor(
                    prompt: String(localized: "输入需要长期保留的事实、偏好或工作约定"),
                    text: $settings.longTermMemory,
                    lineLimit: 9...16,
                    minimumHeight: 240
                )
            } header: {
                Text("长期记忆")
            } footer: {
                Text("任务与聊天共享这份记忆。聊天结束后会自动整理值得保留的信息。")
            }

            if appModel.chatCoordinator.sharedMemory.isUpdating {
                Section {
                    HStack(spacing: AppDesign.compactSpacing) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在整理共享记忆…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage = appModel.chatCoordinator.sharedMemory.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("今日记忆") {
                if trimmedTodayMemory.isEmpty {
                    Color.clear
                        .frame(minHeight: 96)
                        .accessibilityHidden(true)
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
        .task(id: appModel.chatCoordinator.sharedMemory.isUpdating) {
            await settings.load()
        }
        .task(id: [settings.longTermMemory, settings.persistedLongTermMemory]) {
            await autoSave(settings.longTermMemory)
        }
        .onDisappear(perform: savePendingChanges)
    }

    private var trimmedTodayMemory: String {
        appModel.memorySettings.todayMemory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func autoSave(_ content: String) async {
        guard let persistedContent = appModel.memorySettings.persistedLongTermMemory,
              content != persistedContent else {
            return
        }

        do {
            try await Task.sleep(for: AppDesign.settingsAutoSaveDelay)
        } catch {
            return
        }

        guard !Task.isCancelled,
              appModel.memorySettings.longTermMemory == content,
              appModel.memorySettings.persistedLongTermMemory != content else {
            return
        }

        await appModel.memorySettings.save(content)
    }

    private func savePendingChanges() {
        let content = appModel.memorySettings.longTermMemory
        let hasUnsavedChanges = appModel.memorySettings.persistedLongTermMemory
            .map { content != $0 } ?? !content.isEmpty
        guard hasUnsavedChanges else { return }

        Task {
            await appModel.memorySettings.save(content)
        }
    }
}
