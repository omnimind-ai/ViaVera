#if os(macOS)
import SwiftUI

struct MacAppCommands: Commands {
    @FocusedValue(\.macShortcutContext) private var context

    var body: some Commands {
        // Replace the default new-window shortcut so clearing New Conversation
        // also releases Command-N instead of falling back to a new app window.
        CommandGroup(replacing: .newItem) {
            shortcutButton(.newConversation)
            shortcutButton(.quickChat)
        }
        CommandGroup(replacing: .appSettings) {
            shortcutButton(.settings)
        }
        CommandMenu("导航") {
            shortcutButton(.searchConversations)
            shortcutButton(.openTools)
            Divider()
            shortcutButton(.goBack)
            shortcutButton(.goForward)
            Divider()
            shortcutButton(.focusComposer)
            shortcutButton(.terminal)
            shortcutButton(.commands)
        }
    }

    private func shortcutButton(_ action: MacShortcutAction) -> some View {
        Button(action.title) { context?.perform(action) }
            .keyboardShortcut(context?.settings.shortcut(for: action)?.keyboardShortcut)
            .disabled(context?.canPerform(action) != true)
    }
}
#endif
