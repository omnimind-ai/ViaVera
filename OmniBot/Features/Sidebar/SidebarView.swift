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
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ConversationModePicker()
                        .padding(.horizontal, AppDesign.sidebarHorizontalInset)
                        .padding(.top, AppDesign.compactSpacing)
                    SidebarHeaderView(searchText: $searchText)
                    if appModel.conversationMode == .task {
                        SidebarToolsButton()
                            .transition(.opacity)
                    }
                }
                SidebarMacConversationListView(
                    conversations: filteredConversations,
                    isSearching: !searchText.isEmpty
                )
                .id(appModel.conversationMode)
                .transition(.opacity)
            }
#else
            SidebarMobileConversationListView(
                conversations: filteredConversations,
                isSearching: !searchText.isEmpty
            )
            .safeAreaBar(edge: .top, spacing: 0) {
                ConversationModePicker()
                    .padding(.horizontal, AppDesign.mobileSidebarHorizontalInset)
                    .padding(.vertical, AppDesign.compactSpacing)
            }
#endif
        }
#if os(macOS)
        // No navigation title here: the sidebar shares the window toolbar with the
        // detail, whose title belongs after the leading controls. The material also
        // stays below that toolbar, so showing or hiding the sidebar leaves it unchanged.
        .background(.bar, ignoresSafeAreaEdges: [])
#else
        .navigationTitle("Via Vera")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: String(localized: "搜索会话")
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

#if !os(macOS)
    private func showSettings() {
        isShowingSettings = true
    }
#endif

    private var filteredConversations: [ConversationRecord] {
        let historyConversations = appModel.modeConversations.filter { !$0.messages.isEmpty }
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
