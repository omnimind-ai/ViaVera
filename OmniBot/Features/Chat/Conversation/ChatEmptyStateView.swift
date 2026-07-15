import SwiftUI

struct ChatEmptyStateView: View {
    let onSelectPrompt: (String) -> Void

    var body: some View {
        ContentUnavailableView {
            Text("Hi，有什么可以聊的")
        } actions: {
            VStack(spacing: AppDesign.compactSpacing) {
                Button("分析工作区", systemImage: "folder.badge.gearshape", action: selectWorkspacePrompt)
                Button("执行终端任务", systemImage: "terminal", action: selectTerminalPrompt)
                Button("整理项目记忆", systemImage: "brain.head.profile", action: selectMemoryPrompt)
            }
            .padding(.top, AppDesign.standardSpacing)
            .buttonStyle(.bordered)
#if os(iOS)
            .controlSize(.regular)
#else
            .controlSize(.large)
#endif
        }
        .frame(maxWidth: AppDesign.chatContentMaximumWidth)
        .padding(AppDesign.contentPadding)
    }

    private func selectWorkspacePrompt() {
        onSelectPrompt("请分析 /workspace 中的项目结构，并告诉我最值得先处理的问题。")
    }

    private func selectTerminalPrompt() {
        onSelectPrompt("请在本地 Alpine 中执行以下任务：")
    }

    private func selectMemoryPrompt() {
        onSelectPrompt("请根据当前工作区内容整理一份可长期复用的项目记忆。")
    }
}
