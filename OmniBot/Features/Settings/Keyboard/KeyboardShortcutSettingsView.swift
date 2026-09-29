#if os(macOS)
import AppKit
import SwiftUI

struct KeyboardShortcutSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var recording: MacShortcutAction?

    var body: some View {
        let settings = appModel.keyboardShortcuts
        SettingsPageLayout(title: String(localized: "快捷键")) {
            Section {
                VStack(spacing: 0) {
                    ForEach(MacShortcutAction.allCases) { action in
                        KeyboardShortcutSettingsRow(
                            action: action,
                            shortcut: settings.shortcut(for: action),
                            isRecording: recording == action,
                            errorMessage: settings.errorMessage,
                            onRecord: { startRecording(action) },
                            onRemove: {
                                recording = nil
                                settings.clear(action)
                            }
                        )
                        if action != MacShortcutAction.allCases.last { Divider() }
                    }
                }
            } header: {
                Text("常用快捷键")
            } footer: {
                Text("点击铅笔后按下组合键。Esc 取消，Delete 清空；留空即停用。快捷键仅在软件内生效。")
            }
            if recording == nil, let error = settings.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .background {
            if let recording {
                MacShortcutEventMonitor(handleKey: record)
                    .frame(width: 0, height: 0)
                    .id(recording.id)
            }
        }
        .onDisappear {
            recording = nil
            settings.errorMessage = nil
        }
    }

    private func startRecording(_ action: MacShortcutAction) {
        appModel.keyboardShortcuts.errorMessage = nil
        recording = action
    }

    private func record(_ event: NSEvent) -> Bool {
        guard let recording else { return false }
        guard !event.isARepeat else { return true }
        if event.keyCode == 53 {
            self.recording = nil
            appModel.keyboardShortcuts.errorMessage = nil
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if [51, 117].contains(event.keyCode), modifiers.isEmpty {
            appModel.keyboardShortcuts.clear(recording)
            self.recording = nil
            return true
        }
        guard let shortcut = AppKeyboardShortcut(event: event) else { return true }
        if appModel.keyboardShortcuts.assign(shortcut, to: recording) {
            self.recording = nil
        }
        return true
    }
}
#endif
