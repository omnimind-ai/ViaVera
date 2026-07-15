import SwiftUI

struct SidebarConversationActionsModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @State private var renameTitle = ""
    @State private var isShowingRenameAlert = false

    let conversation: ConversationRecord
    let renameRequest: SidebarConversationRenameRequest?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(
                    conversation.isPinned ? "取消置顶" : "置顶",
                    systemImage: conversation.isPinned ? "pin.slash" : "pin",
                    action: togglePinned
                )

                Button("重命名会话", systemImage: "pencil", action: beginRenaming)

                Button("删除会话", systemImage: "trash", role: .destructive) {
                    deleteConversation()
                }
            }
            .alert("重命名会话", isPresented: $isShowingRenameAlert) {
                TextField("会话名称", text: $renameTitle)

                Button("取消", role: .cancel, action: cancelRenaming)
                Button("保存", action: saveRename)
                    .disabled(normalizedRenameTitle.isEmpty)
            } message: {
                Text("请输入新的会话名称。")
            }
            .onChange(of: renameRequest) { _, request in
                guard request?.conversationID == conversation.id else { return }
                beginRenaming()
            }
    }

    private var normalizedRenameTitle: String {
        renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginRenaming() {
        renameTitle = conversation.title
        isShowingRenameAlert = true
    }

    private func cancelRenaming() {
        renameTitle = ""
    }

    private func saveRename() {
        appModel.renameConversation(conversation, to: normalizedRenameTitle)
        renameTitle = ""
    }

    private func togglePinned() {
        appModel.toggleConversationPinned(conversation)
    }

    private func deleteConversation() {
        Task {
            await appModel.deleteConversation(conversation)
        }
    }
}

extension View {
    func sidebarConversationActions(
        for conversation: ConversationRecord,
        renameRequest: SidebarConversationRenameRequest? = nil
    ) -> some View {
        modifier(
            SidebarConversationActionsModifier(
                conversation: conversation,
                renameRequest: renameRequest
            )
        )
    }
}
