import SwiftUI

#if os(iOS)
struct InteractiveTerminalPresentationView: View {
    @Environment(AppModel.self) private var appModel

    let onDismiss: () -> Void

    var body: some View {
        let model = appModel.interactiveTerminal

        NavigationStack {
            InteractiveTerminalView(model: model)
                .navigationTitle("终端")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", action: onDismiss)
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu("终端操作", systemImage: "ellipsis") {
                            Button("显示键盘", systemImage: "keyboard", action: focusKeyboard)
                                .disabled(!model.state.acceptsInput)
                            Button("停止终端", systemImage: "stop", action: model.stop)
                                .disabled(!model.state.acceptsInput)
                        }

                        Button("新建终端", systemImage: "plus", action: model.startNewSession)
                            .disabled(model.state == .stopping)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func focusKeyboard() {
        appModel.interactiveTerminal.requestKeyboardFocus()
    }
}
#endif
