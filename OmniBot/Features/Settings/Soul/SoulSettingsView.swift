import SwiftUI

struct SoulSettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.soulSettings

        SettingsPageLayout(title: "Soul") {
            Section {
                SettingsTextEditor(
                    prompt: String(localized: "描述 Agent 的身份、语气、原则与边界"),
                    text: $settings.content,
                    lineLimit: 8...16,
                    minimumHeight: 220
                )
                .accessibilityLabel("任务模式系统提示")
            } header: {
                Text("任务模式")
            } footer: {
                Text("用于任务执行，定义 Agent 的身份、语气、原则与边界。")
            }

            Section {
                SettingsTextEditor(
                    prompt: String(localized: "描述聊天伙伴的身份、语气与交流方式"),
                    text: $settings.chatContent,
                    lineLimit: 8...16,
                    minimumHeight: 220
                )
                .accessibilityLabel("聊天模式系统提示")
            } header: {
                Text("聊天模式")
            } footer: {
                Text("仅用于聊天，与任务模式独立。聊天共享记忆，但不会调用工具或访问工作空间。")
            }

            if let errorMessage = settings.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .task(id: [settings.content, settings.persistedContent]) {
            await autoSave(settings.content, mode: .task)
        }
        .task(id: [settings.chatContent, settings.persistedChatContent]) {
            await autoSave(settings.chatContent, mode: .chat)
        }
        .onDisappear(perform: savePendingChanges)
    }

    private func autoSave(_ content: String, mode: ConversationMode) async {
        let baseline = persistedContent(for: mode)
        guard let persistedContent = baseline,
              content != persistedContent else {
            return
        }

        do {
            try await Task.sleep(for: AppDesign.settingsAutoSaveDelay)
        } catch {
            return
        }

        guard !Task.isCancelled,
              currentContent(for: mode) == content else {
            return
        }

        await save(content, mode: mode)
    }

    private func savePendingChanges() {
        let content = currentContent(for: .task)
        let chatContent = currentContent(for: .chat)
        let saveTask = persistedContent(for: .task).map { content != $0 } ?? !content.isEmpty
        let saveChat = persistedContent(for: .chat).map { chatContent != $0 } ?? !chatContent.isEmpty
        guard saveTask || saveChat else { return }

        // Capture both snapshots before the view disappears. An in-flight
        // autosave must not replace the text being flushed for either mode.
        Task {
            if saveTask { await appModel.soulSettings.save(content) }
            if saveChat { await appModel.soulSettings.saveChat(chatContent) }
        }
    }

    private func currentContent(for mode: ConversationMode) -> String {
        mode == .chat ? appModel.soulSettings.chatContent : appModel.soulSettings.content
    }

    private func persistedContent(for mode: ConversationMode) -> String? {
        mode == .chat ? appModel.soulSettings.persistedChatContent : appModel.soulSettings.persistedContent
    }

    private func save(_ content: String, mode: ConversationMode) async {
        if mode == .chat {
            await appModel.soulSettings.saveChat(content)
        } else {
            await appModel.soulSettings.save(content)
        }
    }
}
