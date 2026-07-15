import SwiftUI

struct UserMessageBubble: View {
#if os(iOS)
    @GestureState private var isContextMenuPressing = false
    @State private var isContextMenuPresented = false
#endif

    let message: MessageRecord
    let canEditAndRetry: Bool
    let onEdit: () -> Void
    let onRetry: () -> Void
    let onContextMenuInteractionChanged: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 44)

            if hasVisibleContent {
                Group {
                    if canEditAndRetry {
                        Button(action: onEdit) {
                            UserMessageContentView(content: content, showsEditAffordance: true)
                        }
#if os(iOS)
                        .buttonStyle(UserMessageEditButtonStyle())
#else
                        .buttonStyle(.plain)
#endif
                        .frame(minHeight: AppDesign.minimumTouchTarget)
                        .accessibilityHint("在输入框中重新编辑并发送这条消息")
                        .help("编辑这条消息")
                    } else {
                        UserMessageContentView(content: content, showsEditAffordance: false)
                    }
                }
                .accessibilityLabel("你：\(content)")
                .contextMenu {
                    Button("复制", systemImage: "doc.on.doc", action: copyMessage)
#if os(iOS)
                        .onAppear(perform: contextMenuDidAppear)
                        .onDisappear(perform: contextMenuDidDisappear)
#endif

                    if canEditAndRetry {
                        Button("编辑", systemImage: "pencil", action: onEdit)
                        Button("重试这条消息", systemImage: "arrow.clockwise", action: onRetry)
                    }
                }
#if os(iOS)
                // Arm the layout lock before SwiftUI's context-menu recognizer
                // starts its presentation transition.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.15)
                        .updating($isContextMenuPressing) { isPressing, state, _ in
                            state = isPressing
                        }
                )
                .onChange(of: isContextMenuPressing) { _, _ in
                    notifyContextMenuInteractionChanged()
                }
#endif
                .frame(
                    maxWidth: AppDesign.userMessageMaximumWidth,
                    alignment: .trailing
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var content: String {
        message.content ?? ""
    }

    private var hasVisibleContent: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func copyMessage() {
        ChatClipboard.copy(content)
    }

#if os(iOS)
    private func contextMenuDidAppear() {
        isContextMenuPresented = true
        onContextMenuInteractionChanged(true)
    }

    private func contextMenuDidDisappear() {
        isContextMenuPresented = false
        onContextMenuInteractionChanged(isContextMenuPressing)
    }

    private func notifyContextMenuInteractionChanged() {
        onContextMenuInteractionChanged(isContextMenuPressing || isContextMenuPresented)
    }
#endif
}
