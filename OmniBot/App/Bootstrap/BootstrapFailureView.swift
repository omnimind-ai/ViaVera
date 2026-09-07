import SwiftUI

struct BootstrapFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("OmniBot 无法启动", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text(message)
                    .textSelection(.enabled)
                Text("本地数据没有被自动删除。修复 Application Support/OmniBot 中的数据后可重新尝试。")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("重新尝试", systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
