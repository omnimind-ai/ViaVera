#if os(macOS)
import AppKit
import SwiftUI

struct MacShortcutScope: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.macChatShortcutActions) private var chatActions
    var isMainWindow = true

    func body(content: Content) -> some View {
        let context = MacShortcutContext(
            settings: appModel.keyboardShortcuts,
            canPerform: canPerform,
            perform: perform
        )
        content
            .focusedSceneValue(\.macShortcutContext, context)
            .background {
                MacShortcutEventMonitor { event in
                    guard appModel.presentedSettingsDestination == nil,
                          NSApp.modalWindow == nil,
                          let shortcut = AppKeyboardShortcut(event: event) else { return false }
                    if let action = context.settings.action(for: shortcut) {
                        if !event.isARepeat, context.canPerform(action) { context.perform(action) }
                        return true
                    }
                    // Cleared built-ins must not fall through to a navigation
                    // stack's own back action or the system new-window command.
                    return MacShortcutAction.allCases.contains { $0.defaultShortcut == shortcut }
                }
                .frame(width: 0, height: 0)
            }
    }

    private func canPerform(_ action: MacShortcutAction) -> Bool {
        guard appModel.presentedSettingsDestination == nil,
              NSApp.keyWindow?.attachedSheet == nil,
              NSApp.modalWindow == nil else { return false }
        switch action {
        case .goBack: return isMainWindow && appModel.canGoBack
        case .goForward: return isMainWindow && appModel.canGoForward
        case .focusComposer: return chatActions != nil
        case .terminal: return chatActions?.toggleTerminal != nil
        case .commands: return chatActions?.toggleCommands != nil
        default: return true
        }
    }

    private func perform(_ action: MacShortcutAction) {
        guard canPerform(action) else { return }
        switch action {
        case .newConversation: appModel.newConversation()
        case .quickChat: openWindow(id: AppSceneID.detachedChat)
        case .searchConversations:
            appModel.sidebarSearchRequestID &+= 1
            showMainWindowIfNeeded()
        case .openTools:
            appModel.openNativeToolLibrary()
            showMainWindowIfNeeded()
        case .settings:
            appModel.presentSettings()
            showMainWindowIfNeeded()
        case .goBack: appModel.goBack()
        case .goForward: appModel.goForward()
        case .focusComposer: chatActions?.focusComposer()
        case .terminal: chatActions?.toggleTerminal?()
        case .commands: chatActions?.toggleCommands?()
        }
    }

    private func showMainWindowIfNeeded() {
        guard !isMainWindow else { return }
        openWindow(id: AppSceneID.mainWindow, value: AppSceneID.mainWindow)
        NSApp.activate()
    }
}
#endif
