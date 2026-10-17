import SwiftUI

struct ChatEmptyStateView: View {
    let mode: ConversationMode
    let onSelectPrompt: (String) -> Void

    var body: some View {
        ContentUnavailableView {
            Text(mode == .chat
                 ? String(localized: "Hi，今天想聊些什么？")
                 : String(localized: "Hi，有什么可以帮你完成的？"))
        } description: {
            if mode == .chat {
                Text("聊想法、找灵感，或者轻松聊聊。")
            }
        } actions: {
            VStack(spacing: AppDesign.compactSpacing) {
                if mode == .chat {
                    Button("一起想点子", systemImage: "lightbulb") {
                        onSelectPrompt(String(localized: "我有一个想法，想和你一起聊聊："))
                    }
                    Button("帮我理清思路", systemImage: "bubble.left.and.bubble.right") {
                        onSelectPrompt(String(localized: "我想理清一件事，可以陪我一步步想想吗？"))
                    }
                    Button("聊聊今天", systemImage: "sun.max") {
                        onSelectPrompt(String(localized: "我想和你聊聊今天发生的事。"))
                    }
                } else {
                    Button("分析工作区", systemImage: "folder.badge.gearshape", action: selectWorkspacePrompt)
                    Button("执行终端任务", systemImage: "terminal", action: selectTerminalPrompt)
                    Button("整理项目记忆", systemImage: "brain.head.profile", action: selectMemoryPrompt)
                }
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
        onSelectPrompt(String(localized: "请分析 /workspace 中的项目结构，并告诉我最值得先处理的问题。"))
    }

    private func selectTerminalPrompt() {
        onSelectPrompt(String(localized: "请在本地 Alpine 中执行以下任务："))
    }

    private func selectMemoryPrompt() {
        onSelectPrompt(String(localized: "请根据当前工作区内容整理一份可长期复用的项目记忆。"))
    }
}
