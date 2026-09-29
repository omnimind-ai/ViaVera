#if os(macOS)
import SwiftUI

struct ShortcutKeyBadge: View {
    let title: String
    let isRecording: Bool
    let onRecord: () -> Void

    var body: some View {
        Button(action: onRecord) {
            HStack(spacing: 10) {
                Text(isRecording ? String(localized: "请按下快捷键…") : title)
                    .font(.callout.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        isRecording ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: .capsule
                    )
                Image(systemName: "pencil")
                    .accessibilityHidden(true)
            }
            .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("录制快捷键")
        .accessibilityLabel(isRecording ? String(localized: "正在录制快捷键") : String(localized: "录制快捷键"))
        .accessibilityValue(title)
    }
}
#endif
