import SwiftUI

struct TerminalStateOverlay: View {
    let state: InteractiveTerminalState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            ProgressView("正在打开终端…")
        case .preparing(let message):
            ProgressView(message)
        case .stopping:
            ProgressView("正在停止终端…")
        case .failed(let message):
            ContentUnavailableView {
                Label("终端无法启动", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
                    .textSelection(.enabled)
            } actions: {
                Button("重新尝试", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        case .stopped:
            ContentUnavailableView {
                Label("终端已结束", systemImage: "terminal")
            } description: {
                Text("点击右上角加号启动新的终端会话。")
            } actions: {
                Button("新建终端", systemImage: "plus", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        case .running:
            EmptyView()
        }
    }
}
