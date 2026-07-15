import SwiftUI

struct SettingsCodeBlockView: View {
    let text: String
    let minimumHeight: Double

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppDesign.settingsEditorPadding)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(.background, in: .rect(cornerRadius: AppDesign.settingsEditorCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.settingsEditorCornerRadius)
                .strokeBorder(.quaternary, lineWidth: 1)
                .accessibilityHidden(true)
        }
    }
}
