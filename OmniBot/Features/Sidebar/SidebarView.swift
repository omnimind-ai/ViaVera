import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
#if !os(macOS)
    @State private var isShowingSettings = false
#endif

    var body: some View {
        Group {
#if os(macOS)
            SidebarMacConversationListView(
                conversations: filteredConversations,
                isSearching: !searchText.isEmpty
            )
            .safeAreaBar(edge: .top, spacing: 0) {
                SidebarHeaderView(searchText: $searchText)
            }
#else
            SidebarMobileConversationListView(
                conversations: filteredConversations,
                isSearching: !searchText.isEmpty
            )
#endif
        }
#if os(macOS)
        .navigationTitle("OmniBot")
        .background(.bar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("设置", systemImage: "gearshape", action: showSettings)
                    .help("设置")

                Button("新建会话", systemImage: "square.and.pencil", action: appModel.newConversation)
                    .help("新建会话")
            }
        }
#else
        .navigationTitle("Via Vera")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索会话"
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("设置", systemImage: "gearshape", action: showSettings)
                    .accessibilityHint("打开 Agent 与系统设置")
            }

            ToolbarItem(placement: .primaryAction) {
                Button("新建会话", systemImage: "square.and.pencil", action: appModel.newConversation)
                    .accessibilityHint("创建一个新的会话")
            }
        }
#endif
#if !os(macOS)
        .sheet(isPresented: $isShowingSettings) {
            SettingsCardView()
        }
#endif
    }

    private func showSettings() {
#if os(macOS)
        appModel.presentSettings()
#else
        isShowingSettings = true
#endif
    }

    private var filteredConversations: [ConversationRecord] {
        let historyConversations = appModel.conversations.historyConversations
        guard !searchText.isEmpty else {
            return historyConversations
        }

        return historyConversations.filter { conversation in
            conversation.title.localizedStandardContains(searchText)
                || conversation.messages.contains { message in
                    message.content?.localizedStandardContains(searchText) == true
                }
        }
    }

}
