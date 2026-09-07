import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        NavigationSplitView {
            SidebarView()
#if os(macOS)
                .navigationSplitViewColumnWidth(
                    min: AppDesign.sidebarMinimumWidth,
                    ideal: AppDesign.sidebarIdealWidth,
                    max: AppDesign.sidebarMaximumWidth
                )
#endif
        } detail: {
            destinationView
        }
        .navigationSplitViewStyle(.balanced)
#if os(macOS)
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
#endif

    @ViewBuilder
    private var destinationView: some View {
        switch appModel.destination {
        case let .conversation(identifier):
            AgentChatView(conversationID: identifier)
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
        case nil:
            ContentUnavailableView {
                Label("OmniBot", systemImage: "sparkles")
            } description: {
                Text("正在准备本地 Agent…")
            }
        }
    }
}
