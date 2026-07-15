import SwiftUI

#if os(macOS)
struct MacInlineTerminalView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var isKeyboardFocused: Bool

    let onDismiss: () -> Void

    var body: some View {
        let model = appModel.interactiveTerminal

        VStack(spacing: 0) {
            Divider()

            HStack(spacing: AppDesign.compactSpacing) {
                Label("终端", systemImage: "terminal")
                    .font(.callout)

                Spacer()

                Button("新建终端", systemImage: "plus", action: model.startNewSession)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(model.state == .stopping)
                    .help("新建终端")

                Button("关闭终端", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("关闭终端（⌘J）")
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .frame(height: AppDesign.macInlineTerminalHeaderHeight)

            InteractiveTerminalView(
                model: model,
                isKeyboardFocused: $isKeyboardFocused
            )
            .simultaneousGesture(
                TapGesture().onEnded(focusKeyboard)
            )
        }
        .frame(height: AppDesign.macInlineTerminalHeight)
        .background(.bar)
    }

    private func focusKeyboard() {
        guard appModel.interactiveTerminal.state.acceptsInput else { return }
        isKeyboardFocused = true
    }
}
#endif
