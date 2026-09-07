#if os(macOS)
import AppKit
import SwiftUI

struct MenuBarChatView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @State private var windowReference = MenuBarWindowReference()

    let session: MenuBarChatSession
    var isDetached = false

    var body: some View {
        Group {
            if let conversation = appModel.selectedConversation {
                AgentChatView(
                    conversationID: conversation.id,
                    onOpenMainWindow: openMainWindow,
                    onTogglePin: togglePin,
                    isPinned: isDetached && session.isPinned,
                    composerDraft: session.composerDraft
                )
            } else {
                ContentUnavailableView {
                    Label("OmniBot", systemImage: "sparkles")
                } description: {
                    Text("正在准备本地 Agent…")
                } actions: {
                    Button("新建会话", systemImage: "square.and.pencil", action: appModel.newConversation)
                        .disabled(!appModel.hasStarted)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .frame(width: isDetached ? nil : 480, height: isDetached ? nil : 640)
        .background {
            ChatBackgroundView(settings: appModel.appearanceSettings)
                .ignoresSafeArea()
        }
        .symbolRenderingMode(.hierarchical)
        .modifier(AppSceneLifecycleModifier())
        .background {
            MenuBarWindowAccessor(
                reference: windowReference,
                themeMode: appModel.appearanceSettings.themeMode
            )
            .frame(width: 0, height: 0)
        }
    }

    private func togglePin() {
        if isDetached {
            session.isPinned.toggle()
            return
        }

        session.isPinned = true
        openWindow(id: AppSceneID.detachedChat)
        // Hide only the source menu bar window. The independent SwiftUI Window
        // owns its lifecycle and keeps the same conversation and composer draft.
        windowReference.hide()
        NSApplication.shared.activate()
    }

    private func openMainWindow() {
        if let conversation = appModel.selectedConversation {
            appModel.destination = .conversation(conversation.id)
        }
        // A stable value lets SwiftUI focus an existing main window, or recreate
        // it after the user closes it, without opening duplicates on each click.
        openWindow(id: AppSceneID.mainWindow, value: AppSceneID.mainWindow)
        NSApplication.shared.activate()
    }
}
#endif
