import SwiftUI

struct SettingsTextEditor: View {
    let prompt: String
    @Binding var text: String
    let lineLimit: ClosedRange<Int>
    let minimumHeight: Double

    var body: some View {
#if os(macOS)
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(
                    AppDesign.settingsEditorPadding,
                    for: .scrollContent
                )
                .multilineTextAlignment(.leading)
                .accessibilityLabel(prompt)

            if text.isEmpty {
                Text(prompt)
                    .foregroundStyle(.tertiary)
                    .padding(AppDesign.settingsEditorPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .font(.body.monospaced())
        .settingsMultilineInputStyle(
            minimumHeight: minimumHeight,
            maximumHeight: CGFloat(minimumHeight)
        )
#else
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(lineLimit)
            .font(.body.monospaced())
            .settingsMultilineInputStyle(minimumHeight: minimumHeight)
#endif
    }
}
