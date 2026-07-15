#if os(macOS)
import SwiftUI

struct SidebarMacConversationListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var renameRequest: SidebarConversationRenameRequest?

    let conversations: [ConversationRecord]
    let isSearching: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("最近会话")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
                    .accessibilityAddTraits(.isHeader)

                if conversations.isEmpty, isSearching {
                    ContentUnavailableView.search
                        .frame(maxWidth: .infinity)
                } else if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("还没有会话", systemImage: "bubble.left")
                    } description: {
                        Text("新建会话后即可把任务交给 Agent。")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(conversations) { conversation in
                        Button {
                            selectConversation(conversation)
                        } label: {
                            SidebarConversationRow(conversation: conversation)
                                .padding(.horizontal, AppDesign.compactSpacing)
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isActiveConversation(conversation)
                                ? AppDesign.sidebarSelectionBackground
                                : .clear,
                            in: .rect(cornerRadius: AppDesign.compactCornerRadius)
                        )
                        .accessibilityAddTraits(
                            isActiveConversation(conversation) ? .isSelected : []
                        )
                        .simultaneousGesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    requestRename(conversation)
                                }
                        )
                        .sidebarConversationActions(
                            for: conversation,
                            renameRequest: renameRequest
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(
            .horizontal,
            AppDesign.sidebarHorizontalInset,
            for: .scrollContent
        )
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func selectConversation(_ conversation: ConversationRecord) {
        appModel.destination = .conversation(conversation.id)
    }

    private func isActiveConversation(_ conversation: ConversationRecord) -> Bool {
        appModel.destination == .conversation(conversation.id)
    }

    private func requestRename(_ conversation: ConversationRecord) {
        renameRequest = SidebarConversationRenameRequest(conversationID: conversation.id)
    }
}
#endif
