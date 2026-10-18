import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
#if os(macOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSidebarVisible = true
    @State private var isSidebarInteractive = true
    @State private var sidebarTransitionID = 0
#endif

    var body: some View {
        @Bindable var appModel = appModel

        Group {
#if os(iOS)
            MobileAppRootView()
#else
            MacSidebarSplitView(
                isSidebarVisible: isSidebarVisible,
                sidebarWidth: $appModel.sidebarWidth,
                collapseSidebar: { setSidebarVisible(false) }
            ) {
                SidebarView()
                    // Keep keyboard focus out of the hidden list once it has slid away;
                    // disabling it earlier would dim the list during the animation.
                    .disabled(!isSidebarInteractive)
            } detail: {
                destinationView
            }
#endif
        }
#if os(macOS)
        .modifier(MacShortcutScope())
        .toolbar {
            MacWindowNavigationToolbar(isSidebarVisible: isSidebarVisible, toggleSidebar: toggleSidebar)
        }
        .onChange(of: appModel.sidebarSearchRequestID) { _, _ in
            setSidebarVisible(true)
        }
        .background {
            if isConversationDestination {
                ChatBackgroundView(settings: appModel.appearanceSettings)
                    .ignoresSafeArea()
            }
        }
#endif
        .symbolRenderingMode(.hierarchical)
#if os(iOS)
        .sheet(isPresented: $appModel.isTerminalPresented) {
            InteractiveTerminalPresentationView(
                onDismiss: appModel.dismissTerminal
            )
        }
#endif
#if os(macOS)
        .disabled(isSettingsPresented)
        .accessibilityHidden(isSettingsPresented)
        .overlay {
            if let destination = appModel.presentedSettingsDestination {
                SettingsOverlayView(
                    initialDestination: destination,
                    onDismiss: appModel.dismissSettings
                )
            }
        }
#endif
        .modifier(AppSceneLifecycleModifier())
    }

#if os(macOS)
    private var isSettingsPresented: Bool {
        appModel.presentedSettingsDestination != nil
    }

    private var isConversationDestination: Bool {
        if case .conversation = appModel.destination {
            true
        } else {
            false
        }
    }

    private func toggleSidebar() {
        setSidebarVisible(!isSidebarVisible)
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        guard isVisible != isSidebarVisible else { return }
        sidebarTransitionID &+= 1
        let transitionID = sidebarTransitionID
        if isVisible { isSidebarInteractive = true }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            isSidebarVisible = isVisible
        } completion: {
            // A newer toggle owns the sidebar while its own animation runs.
            guard transitionID == sidebarTransitionID else { return }
            isSidebarInteractive = isVisible
        }
    }
#endif

    @ViewBuilder
    private var destinationView: some View {
        switch appModel.destination {
        case let .conversation(identifier):
            AgentChatView(conversationID: identifier, composerDraft: appModel.chatDraft(for: identifier))
                .id(identifier)
                .transition(.opacity)
        case .providers:
            ProviderSettingsView()
        case .soul:
            SoulSettingsView()
        case .memory:
            MemorySettingsView()
        case .skills:
            SkillSettingsView()
        case .runtime:
            AlpineRuntimeView()
        case .tools:
            NativeToolsRootView()
        case nil:
            ContentUnavailableView {
                Label("OmniBot", systemImage: "sparkles")
            } description: {
                Text("正在准备本地 Agent…")
            }
            .navigationTitle("OmniBot")
        }
    }
}
