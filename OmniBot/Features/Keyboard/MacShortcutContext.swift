#if os(macOS)
import SwiftUI

struct MacShortcutContext {
    let settings: KeyboardShortcutSettingsModel
    let canPerform: (MacShortcutAction) -> Bool
    let perform: (MacShortcutAction) -> Void
}

private struct MacShortcutContextKey: FocusedValueKey {
    typealias Value = MacShortcutContext
}

extension FocusedValues {
    var macShortcutContext: MacShortcutContext? {
        get { self[MacShortcutContextKey.self] }
        set { self[MacShortcutContextKey.self] = newValue }
    }
}
#endif
