#if !os(macOS)
import SwiftUI

struct SidebarMobileConversationListView: View {
    @Environment(AppModel.self) private var appModel

    let conversations: [ConversationRecord]
    let isSearching: Bool

    var body: some View {
        @Bindable var appModel = appModel

        List(selection: $appModel.destination) {
            if conversations.isEmpty, isSearching {
                ContentUnavailableView.search
                    .listRowSeparator(.hidden)
            } else if conversations.isEmpty {
                ContentUnavailableView {
                    Label("还没有会话", systemImage: "bubble.left")
                } description: {
                    Text("新建会话后即可把任务交给 Agent。")
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(SidebarConversationGroup.allCases) { group in
                    let conversations = groupedConversations[group, default: []]

                    if !conversations.isEmpty {
                        Section(group.title) {
                            ForEach(conversations) { conversation in
                                NavigationLink(value: AppDestination.conversation(conversation.id)) {
                                    SidebarConversationRow(conversation: conversation)
                                }
                                .navigationLinkIndicatorVisibility(.hidden)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: AppDesign.mobileSidebarRowVerticalInset,
                                        leading: AppDesign.mobileSidebarHorizontalInset,
                                        bottom: AppDesign.mobileSidebarRowVerticalInset,
                                        trailing: AppDesign.mobileSidebarHorizontalInset
                                    )
                                )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .sidebarConversationActions(for: conversation)
                            }
                            .onDelete { offsets in
                                deleteConversations(at: offsets, from: conversations)
                            }
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
    }

    private var groupedConversations: [SidebarConversationGroup: [ConversationRecord]] {
        let calendar = Calendar.autoupdatingCurrent
        let referenceDate = Date.now

        return Dictionary(grouping: conversations) { conversation in
            SidebarConversationGroup.group(
                for: conversation.updatedAt,
                isPinned: conversation.isPinned,
                relativeTo: referenceDate,
                calendar: calendar
            )
        }
    }

    private func deleteConversation(_ conversation: ConversationRecord) {
        Task {
            await appModel.deleteConversation(conversation)
        }
    }

    private func deleteConversations(
        at offsets: IndexSet,
        from conversations: [ConversationRecord]
    ) {
        for index in offsets.sorted(by: >) where conversations.indices.contains(index) {
            deleteConversation(conversations[index])
        }
    }
}
#endif
