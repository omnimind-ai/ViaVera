#if os(iOS)
import SwiftUI

struct MobileAppRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: $appModel.selectedTab) {
            Tab("聊天", systemImage: "bubble.left.and.bubble.right", value: .conversations) {
                NavigationStack(path: $appModel.conversationPath) {
                    SidebarView()
                        .navigationDestination(for: UUID.self) { id in
                            AgentChatView(conversationID: id, composerDraft: appModel.chatDraft(for: id))
                                .id(id)
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
            }
            Tab("工具", systemImage: "square.grid.2x2", value: .tools) {
                NativeToolsRootView()
            }
        }
    }
}
#endif
