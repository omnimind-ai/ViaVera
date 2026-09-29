#if os(macOS)
import Foundation

struct AppKeyboardShortcut: Codable, Hashable {
    let key: String
    let modifiers: ShortcutModifiers

    init(key: String, modifiers: ShortcutModifiers) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    var validationMessage: String? {
        guard key.count == 1, key == key.lowercased(),
              modifiers.subtracting(.supported).isEmpty,
              let scalar = key.unicodeScalars.first,
              scalar.value >= 32 || [9, 13, 127].contains(scalar.value) else {
            return String(localized: "无法使用这个按键，请录制其他组合。")
        }
        guard !modifiers.intersection([.command, .control]).isEmpty else {
            return String(localized: "请包含 Command 或 Control 键，避免影响正常输入。")
        }
        if modifiers.contains(.command), ["a", "c", "v", "x", "z", "q", "w", "m", "h", "\t", " "].contains(key) {
            return String(localized: "这个组合用于系统或文本编辑，请使用其他快捷键。")
        }
        return nil
    }

    var displayName: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        let specialKeys = ["\r": "↩", "\t": "⇥", " ": "Space", "\u{7F}": "⌫",
                           "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→",
                           "\u{F728}": "⌦", "\u{F729}": "↖", "\u{F72B}": "↘",
                           "\u{F72C}": "⇞", "\u{F72D}": "⇟"]
        if let title = specialKeys[key] {
            return result + title
        }
        if let value = key.unicodeScalars.first?.value, (0xF704...0xF726).contains(value) {
            return result + "F\(value - 0xF704 + 1)"
        }
        return result + key.uppercased()
    }
}
#endif
