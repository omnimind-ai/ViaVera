#if os(iOS)
import SwiftUI

struct MobileAppRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: $appModel.selectedTab) {
            Tab(
                appModel.conversationMode.title,
                systemImage: appModel.conversationMode == .chat ? "bubble.left.and.bubble.right" : "checklist",
                value: .conversations
            ) {
                NavigationStack(path: $appModel.conversationPath) {
                    SidebarView()
                        .navigationDestination(for: UUID.self) { id in
                            AgentChatView(conversationID: id, composerDraft: appModel.chatDraft(for: id))
                                .id(id)
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
            }
            if appModel.conversationMode == .task {
                Tab(String(localized: "工具"), systemImage: "square.grid.2x2", value: .tools) {
                    NativeToolsRootView()
                }
            }
        }
    }
}
#endif
