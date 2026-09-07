#if os(macOS)
import SwiftUI

struct MenuBarChatHeader<Actions: View>: View {
    @Environment(AppModel.self) private var appModel

    let title: String
    let onNewConversation: () -> Void
    let onOpenMainWindow: () -> Void
    let isPinned: Bool
    let onTogglePin: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        @Bindable var appModel = appModel

        HStack(spacing: AppDesign.compactSpacing) {
            Menu {
                Picker("会话", selection: $appModel.destination) {
                    ForEach(appModel.conversations.conversations) { conversation in
                        Text(conversation.title)
                            .tag(AppDestination.conversation(conversation.id))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    ChatHeaderTitle(title: title)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("切换会话")
            .accessibilityLabel("切换会话")
            .accessibilityValue(title)

            Spacer(minLength: AppDesign.standardSpacing)

            HStack(spacing: AppDesign.compactSpacing) {
                Button("新建会话", systemImage: "square.and.pencil", action: onNewConversation)
                    .help("新建会话")

                Button(
                    isPinned ? "取消置顶" : "置顶窗口",
                    systemImage: isPinned ? "pin.fill" : "pin",
                    action: onTogglePin
                )
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .help(isPinned ? "取消窗口置顶" : "将聊天独立为置顶窗口")
                .accessibilityValue(isPinned ? "已置顶" : "未置顶")

                Button("在主窗口打开", systemImage: "arrow.up.right.square", action: onOpenMainWindow)
                    .help("在主窗口打开当前会话")

                actions
            }
            .fixedSize()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, AppDesign.contentPadding)
        .padding(.vertical, AppDesign.compactSpacing)
    }
}
#endif
