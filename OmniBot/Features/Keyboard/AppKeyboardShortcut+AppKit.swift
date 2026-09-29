#if os(macOS)
import AppKit
import SwiftUI

extension AppKeyboardShortcut {
    init?(event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers, key.count == 1 else { return nil }
        var modifiers: ShortcutModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        self.init(key: key, modifiers: modifiers)
    }

    var keyboardShortcut: KeyboardShortcut? {
        guard let character = key.first else { return nil }
        var flags: EventModifiers = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags)
    }
}
#endif
