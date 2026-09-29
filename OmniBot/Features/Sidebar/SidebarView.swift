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
                VStack(spacing: 0) {
                    SidebarHeaderView(searchText: $searchText)
                    SidebarToolsButton()
                }
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
        .toolbar(removing: isSettingsPresented ? .sidebarToggle : nil)
        .toolbar {
            if isSettingsPresented {
                // Recreate the group because updating its visibility in place leaves
                // the old glass container behind on macOS.
                ToolbarItemGroup(placement: .primaryAction) {
                    settingsToolbarActions
                }
                .sharedBackgroundVisibility(.hidden)

                // Navigation is blocked by the modal. Keep only the subdued symbol;
                // the real system sidebar toggle returns when settings closes.
                ToolbarItem(placement: .primaryAction) {
                    Image(systemName: "sidebar.left")
                        .imageScale(.large)
                        .foregroundStyle(.quaternary)
                        .accessibilityHidden(true)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    settingsToolbarActions
                }
            }
        }
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

#if os(macOS)
    private var isSettingsPresented: Bool {
        appModel.presentedSettingsDestination != nil
    }

    @ViewBuilder
    private var settingsToolbarActions: some View {
        Button("设置", systemImage: "gearshape", action: showSettings)
            .help("设置")
            .disabled(appModel.presentedSettingsDestination != nil)

        Button("后退", systemImage: "chevron.left", action: appModel.goBack)
            .help("后退")
            .disabled(!appModel.canGoBack)

        Button("前进", systemImage: "chevron.right", action: appModel.goForward)
            .help("前进")
            .disabled(!appModel.canGoForward)

        Button("新建会话", systemImage: "square.and.pencil", action: appModel.newConversation)
            .help("新建会话")
            .disabled(appModel.presentedSettingsDestination != nil)
    }
#endif

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
