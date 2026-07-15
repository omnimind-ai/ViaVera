import SwiftUI

struct ComposerSendButton: View {
    let isRunning: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Button(action: performAction) {
            Label {
                Text(isRunning ? "停止" : "发送")
            } icon: {
                Image(systemName: isRunning ? "stop.fill" : "arrow.up")
            }
            .labelStyle(.iconOnly)
        }
        .font(AppDesign.composerControlFont.bold())
        .symbolRenderingMode(.monochrome)
        .composerControlFrame()
        .buttonBorderShape(.circle)
        .buttonStyle(.glassProminent)
        .tint(isRunning ? Color.red : Color.accentColor)
        .disabled(!isEnabled)
        .accessibilityLabel(isRunning ? "停止" : "发送")
        .accessibilityHint(isRunning ? "停止当前 Agent 运行" : "发送消息并启动 Agent")
        .help(isRunning ? "停止当前 Agent 运行" : "发送消息")
    }

    private var isEnabled: Bool {
        isRunning || canSend
    }

    private func performAction() {
        if isRunning {
            onCancel()
        } else {
            onSend()
        }
    }
}
