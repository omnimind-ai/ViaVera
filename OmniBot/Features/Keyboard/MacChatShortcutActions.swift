#if os(macOS)
import SwiftUI

struct MacChatShortcutActions {
    let focusComposer: () -> Void
    let toggleTerminal: (() -> Void)?
    let toggleCommands: (() -> Void)?
}

private struct MacChatShortcutActionsKey: FocusedValueKey {
    typealias Value = MacChatShortcutActions
}

extension FocusedValues {
    var macChatShortcutActions: MacChatShortcutActions? {
        get { self[MacChatShortcutActionsKey.self] }
        set { self[MacChatShortcutActionsKey.self] = newValue }
    }
}
#endif
