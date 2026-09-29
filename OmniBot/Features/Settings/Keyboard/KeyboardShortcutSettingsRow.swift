#if os(macOS)
import SwiftUI

struct KeyboardShortcutSettingsRow: View {
    let action: MacShortcutAction
    let shortcut: AppKeyboardShortcut?
    let isRecording: Bool
    let errorMessage: String?
    let onRecord: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppDesign.standardSpacing) {
            VStack(alignment: .leading, spacing: 5) {
                Text(action.title)
                    .font(.body.weight(.medium))
                Text(action.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ShortcutKeyBadge(
                        title: shortcut?.displayName ?? String(localized: "未分配"),
                        isRecording: isRecording,
                        onRecord: onRecord
                    )
                    Spacer(minLength: 0)
                    if let shortcut {
                        Button("清空快捷键", systemImage: "trash", action: onRemove)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("清空快捷键")
                            .accessibilityLabel(Text("清空\(action.title)的快捷键\(shortcut.displayName)"))
                    }
                }
                if isRecording, let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 220, alignment: .leading)
        }
        .padding(.vertical, AppDesign.standardSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(action.title)
    }
}
#endif
