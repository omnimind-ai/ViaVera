#if os(macOS)
import SwiftUI

struct MacWindowNavigationToolbar: ToolbarContent {
    @Environment(AppModel.self) private var appModel
    let isSidebarVisible: Bool
    let toggleSidebar: () -> Void

    var body: some ToolbarContent {
        MacWindowNavigationControls(
            canGoBack: appModel.canGoBack,
            canGoForward: appModel.canGoForward,
            isSettingsPresented: appModel.presentedSettingsDestination != nil,
            isSidebarVisible: isSidebarVisible,
            showSettings: { appModel.presentSettings() },
            goBack: appModel.goBack,
            goForward: appModel.goForward,
            newConversation: appModel.newConversation,
            toggleSidebar: toggleSidebar
        )
    }
}

struct MacWindowNavigationControls: ToolbarContent {
    let canGoBack: Bool
    let canGoForward: Bool
    let isSettingsPresented: Bool
    let isSidebarVisible: Bool
    let showSettings: () -> Void
    let goBack: () -> Void
    let goForward: () -> Void
    let newConversation: () -> Void
    let toggleSidebar: () -> Void

    private var sidebarToggleTitle: String {
        isSidebarVisible ? String(localized: "隐藏边栏") : String(localized: "显示边栏")
    }

    var body: some ToolbarContent {
        if isSettingsPresented {
            // Recreate the group because updating its visibility in place leaves
            // the old glass container behind on macOS.
            ToolbarItemGroup(placement: .navigation) {
                navigationActions
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            // One group owns every leading control, including the sidebar toggle,
            // so expanding or collapsing the sidebar never reorders or resizes it.
            ToolbarItemGroup(placement: .navigation) {
                navigationActions
            }
        }
    }

    @ViewBuilder
    private var navigationActions: some View {
        Button("设置", systemImage: "gearshape", action: showSettings)
            .help("设置")
            .disabled(isSettingsPresented)

        Button("后退", systemImage: "chevron.left", action: goBack)
            .help("后退")
            .disabled(!canGoBack)

        Button("前进", systemImage: "chevron.right", action: goForward)
            .help("前进")
            .disabled(!canGoForward)

        Button("新建会话", systemImage: "square.and.pencil", action: newConversation)
            .help("新建会话")
            .disabled(isSettingsPresented)

        Button(sidebarToggleTitle, systemImage: "sidebar.left", action: toggleSidebar)
            .help(sidebarToggleTitle)
            .disabled(isSettingsPresented)
    }
}
#endif
