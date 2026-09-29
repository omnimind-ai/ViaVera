#if os(macOS)
import Foundation

/// A saved nil shortcut explicitly disables the action's default binding.
struct KeyboardShortcutBinding: Codable {
    let shortcut: AppKeyboardShortcut?
}
#endif
