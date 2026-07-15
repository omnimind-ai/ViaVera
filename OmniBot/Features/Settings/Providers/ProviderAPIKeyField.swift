import SwiftUI

struct ProviderAPIKeyField: View {
    @Binding var apiKey: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: AppDesign.compactSpacing) {
            if isRevealed {
                TextField("请输入 API Key", text: $apiKey)
                    .textFieldStyle(.plain)
            } else {
                SecureField("请输入 API Key", text: $apiKey)
                    .textFieldStyle(.plain)
            }

            Button(
                isRevealed ? "隐藏 API Key" : "显示 API Key",
                systemImage: isRevealed ? "eye.slash" : "eye",
                action: toggleVisibility
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
        }
        .autocorrectionDisabled()
        .settingsInputStyle()
        .accessibilityElement(children: .contain)
#if os(iOS)
        .textInputAutocapitalization(.never)
#endif
    }

    private func toggleVisibility() {
        isRevealed.toggle()
    }
}
