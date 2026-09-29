#if os(macOS)
import Foundation
import Observation

@MainActor
@Observable
final class KeyboardShortcutSettingsModel {
    static let storageKey = "via-vera.keyboard-shortcuts.v1"
    private var overrides: [String: KeyboardShortcutBinding]
    var errorMessage: String?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: KeyboardShortcutBinding].self, from: $0) } ?? [:]
        var used = Set<AppKeyboardShortcut>()
        var cleaned: [String: KeyboardShortcutBinding] = [:]
        for action in MacShortcutAction.allCases {
            let binding = stored[action.rawValue] ?? KeyboardShortcutBinding(shortcut: action.defaultShortcut)
            if let shortcut = binding.shortcut,
               shortcut.validationMessage != nil || !used.insert(shortcut).inserted {
                cleaned[action.rawValue] = KeyboardShortcutBinding(shortcut: nil)
            } else if stored[action.rawValue] != nil {
                cleaned[action.rawValue] = binding
            }
        }
        overrides = cleaned
    }

    func shortcut(for action: MacShortcutAction) -> AppKeyboardShortcut? {
        if let binding = overrides[action.rawValue] { return binding.shortcut }
        return action.defaultShortcut
    }

    func action(for shortcut: AppKeyboardShortcut) -> MacShortcutAction? {
        MacShortcutAction.allCases.first { self.shortcut(for: $0) == shortcut }
    }

    @discardableResult
    func assign(_ shortcut: AppKeyboardShortcut, to action: MacShortcutAction) -> Bool {
        errorMessage = shortcut.validationMessage
        guard errorMessage == nil else { return false }
        for candidate in MacShortcutAction.allCases where candidate != action {
            if self.shortcut(for: candidate) == shortcut {
                errorMessage = String(localized: "此快捷键已用于「\(candidate.title)」。请先清除原绑定，或使用其他组合。")
                return false
            }
        }
        return save(shortcut, for: action)
    }

    func clear(_ action: MacShortcutAction) {
        _ = save(nil, for: action)
    }

    private func save(_ shortcut: AppKeyboardShortcut?, for action: MacShortcutAction) -> Bool {
        var updated = overrides
        updated[action.rawValue] = KeyboardShortcutBinding(shortcut: shortcut)
        do {
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: Self.storageKey)
            overrides = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
#endif
