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
        .overlay {
            if let destination = appModel.presentedSettingsDestination {
                SettingsOverlayView(
                    initialDestination: destination,
                    onDismiss: appModel.dismissSettings
                )
            }
        }
#endif
        .task {
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                return
            }
            await appModel.start()
        }
        .alert(
            "OmniBot 出现问题",
            isPresented: Binding(
                get: { appModel.globalErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appModel.globalErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                appModel.globalErrorMessage = nil
            }
        } message: {
            Text(appModel.globalErrorMessage ?? "未知错误")
        }
    }

#if os(macOS)
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
