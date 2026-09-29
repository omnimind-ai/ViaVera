#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import Via_Vera

@Suite("Keyboard shortcut settings")
@MainActor
struct KeyboardShortcutSettingsTests {
    private func withSettings(_ test: (KeyboardShortcutSettingsModel, UserDefaults) throws -> Void) throws {
        let name = "KeyboardShortcutSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try test(KeyboardShortcutSettingsModel(defaults: defaults), defaults)
    }

    @Test("Defaults are valid, unique and keep the existing navigation and terminal shortcuts")
    func defaults() throws {
        try withSettings { settings, _ in
            let shortcuts = MacShortcutAction.allCases.compactMap { settings.shortcut(for: $0) }
            #expect(shortcuts.allSatisfy { $0.validationMessage == nil })
            #expect(Set(shortcuts).count == shortcuts.count)
            #expect(settings.action(for: .init(key: "[", modifiers: .command)) == .goBack)
            #expect(settings.action(for: .init(key: "]", modifiers: .command)) == .goForward)
            #expect(settings.action(for: .init(key: "j", modifiers: .command)) == .terminal)
            #expect(settings.shortcut(for: .commands) == nil)
        }
    }

    @Test("Clearing a default stays disabled after reloading instead of restoring its fallback")
    func clearedBindingPersists() throws {
        try withSettings { settings, defaults in
            settings.clear(.newConversation)
            #expect(settings.shortcut(for: .newConversation) == nil)
            #expect(settings.action(for: .init(key: "n", modifiers: .command)) == nil)
            let reloaded = KeyboardShortcutSettingsModel(defaults: defaults)
            #expect(reloaded.shortcut(for: .newConversation) == nil)
            #expect(reloaded.action(for: .init(key: "n", modifiers: .command)) == nil)
            #expect(reloaded.shortcut(for: .settings) == MacShortcutAction.settings.defaultShortcut)
        }
    }

    @Test("Re-recording releases the old shortcut immediately and survives reload")
    func replaceBinding() throws {
        try withSettings { settings, defaults in
            let replacement = AppKeyboardShortcut(key: "b", modifiers: [.control, .shift])
            #expect(settings.assign(replacement, to: .goBack))
            #expect(settings.action(for: .init(key: "[", modifiers: .command)) == nil)
            #expect(settings.action(for: replacement) == .goBack)
            #expect(KeyboardShortcutSettingsModel(defaults: defaults).shortcut(for: .goBack) == replacement)
        }
    }

    @Test("Each action stores exactly one combination when re-recorded")
    func singleBinding() throws {
        try withSettings { settings, defaults in
            let replacement = AppKeyboardShortcut(key: "o", modifiers: [.shift, .command])
            let next = AppKeyboardShortcut(key: "b", modifiers: [.control, .command])
            #expect(settings.assign(replacement, to: .newConversation))
            #expect(settings.assign(next, to: .newConversation))
            #expect(settings.action(for: replacement) == nil)
            #expect(settings.shortcut(for: .newConversation) == next)
            #expect(KeyboardShortcutSettingsModel(defaults: defaults).shortcut(for: .newConversation) == next)
        }
    }

    @Test("Conflicts leave both actions intact, including their persisted assignments")
    func rejectsConflict() throws {
        try withSettings { settings, defaults in
            let search = try #require(settings.shortcut(for: .searchConversations))
            let original = settings.shortcut(for: .newConversation)
            #expect(!settings.assign(search, to: .newConversation))
            #expect(settings.errorMessage != nil)
            #expect(settings.shortcut(for: .newConversation) == original)
            #expect(settings.action(for: search) == .searchConversations)
            #expect(KeyboardShortcutSettingsModel(defaults: defaults).shortcut(for: .newConversation) == original)
            #expect(settings.assign(search, to: .searchConversations))
            #expect(settings.errorMessage == nil)
        }
    }

    @Test("A cleared shortcut can be reassigned to a different action without a conflict on restart")
    func reassignClearedBinding() throws {
        try withSettings { settings, defaults in
            let newChat = try #require(settings.shortcut(for: .newConversation))
            settings.clear(.newConversation)
            #expect(settings.assign(newChat, to: .commands))
            let reloaded = KeyboardShortcutSettingsModel(defaults: defaults)
            #expect(reloaded.shortcut(for: .newConversation) == nil)
            #expect(reloaded.action(for: newChat) == .commands)
        }
    }

    @Test("Typing keys, unsupported modifiers and reserved system combinations cannot be assigned")
    func invalidBindings() throws {
        try withSettings { settings, _ in
            let invalid: [AppKeyboardShortcut] = [
                .init(key: "n", modifiers: []), .init(key: "n", modifiers: .shift),
                .init(key: "n", modifiers: .option), .init(key: "q", modifiers: .command),
                .init(key: "v", modifiers: [.shift, .command]), .init(key: "", modifiers: .command),
                .init(key: "ab", modifiers: .command), .init(key: "n", modifiers: .init(rawValue: 256)),
                .init(key: "\u{1B}", modifiers: .command)
            ]
            for value in invalid {
                #expect(!settings.assign(value, to: .commands))
                #expect(settings.shortcut(for: .commands) == nil)
            }
        }
    }

    @Test("Stored empty bindings stay empty while invalid or duplicate bindings are discarded")
    func sanitizeStoredBindings() throws {
        try withSettings { _, defaults in
            let stored: [String: KeyboardShortcutBinding] = [
                "newConversation": .init(shortcut: nil),
                "quickChat": .init(shortcut: .init(key: "q", modifiers: .command)),
                "commands": .init(shortcut: .init(key: "j", modifiers: .command)),
                "futureAction": .init(shortcut: .init(key: "f", modifiers: .command))
            ]
            defaults.set(try JSONEncoder().encode(stored), forKey: KeyboardShortcutSettingsModel.storageKey)
            let reloaded = KeyboardShortcutSettingsModel(defaults: defaults)
            #expect(reloaded.shortcut(for: .newConversation) == nil)
            #expect(reloaded.shortcut(for: .commands) == nil)
            #expect(reloaded.action(for: .init(key: "j", modifiers: .command)) == .terminal)
        }
    }

    @Test("Corrupted settings do not break loading")
    func corruptedSettings() throws {
        try withSettings { _, defaults in
            defaults.set(Data("not json".utf8), forKey: KeyboardShortcutSettingsModel.storageKey)
            let settings = KeyboardShortcutSettingsModel(defaults: defaults)
            #expect(settings.shortcut(for: .newConversation) == MacShortcutAction.newConversation.defaultShortcut)
        }
    }

    @Test("Native events normalize case and ignore Caps Lock without losing shortcut modifiers")
    func nativeEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [.command, .option, .shift, .capsLock], timestamp: 0, windowNumber: 0,
            context: nil, characters: "N", charactersIgnoringModifiers: "N", isARepeat: false, keyCode: 45
        ))
        let shortcut = try #require(AppKeyboardShortcut(event: event))
        #expect(shortcut == .init(key: "n", modifiers: [.option, .shift, .command]))
        #expect(shortcut.displayName == "⌥⇧⌘N")
        #expect(shortcut.keyboardShortcut != nil)
    }

    @Test("Special keys have readable badges")
    func readableSpecialKeys() {
        #expect(AppKeyboardShortcut(key: "\r", modifiers: .command).displayName == "⌘↩")
        #expect(AppKeyboardShortcut(key: "\u{F702}", modifiers: .control).displayName == "⌃←")
        #expect(AppKeyboardShortcut(key: "\u{F704}", modifiers: .command).displayName == "⌘F1")
    }
}
#endif
