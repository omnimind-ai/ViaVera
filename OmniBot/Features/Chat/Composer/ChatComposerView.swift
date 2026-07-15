import SwiftUI

struct ChatComposerView: View {
    @Binding var text: String

#if os(macOS)
    @State private var macTextHeight = AppDesign.composerTextLineHeight
    @State private var macTextHasVisibleContent = false
#endif

    let conversation: ConversationRecord
    let isBusy: Bool
    let isRunning: Bool
    let isPreparingResend: Bool
    let isEditingUserMessage: Bool
    let isCommandToolbarPresented: Bool
#if os(macOS)
    let isFocused: Binding<Bool>
#else
    let isFocused: FocusState<Bool>.Binding
#endif
    let focusRequestID: Int
    let busyStatusMessage: String?
    let onInteraction: () -> Void
    let onToggleCommandToolbar: () -> Void
    let onSend: () -> Void
    let onCancel: () -> Void
    let onOpenTerminal: () -> Void
    let onImportAttachments: () -> Void
    let onAddPhotos: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
#if os(macOS)
                ZStack(alignment: .topLeading) {
                    MacChatComposerTextView(
                        text: $text,
                        measuredHeight: $macTextHeight,
                        isFocused: isFocused,
                        hasVisibleContent: $macTextHasVisibleContent,
                        isEnabled: !isTextEntryDisabled,
                        maximumLines: AppDesign.composerMaximumLines,
                        onSubmit: submit
                    )
                    .frame(height: macTextHeight)

                    if text.isEmpty && !macTextHasVisibleContent {
                        Text("发送消息给 OmniBot")
                            .font(AppDesign.composerTextFont)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(
                    minHeight: AppDesign.composerTextLineHeight,
                    alignment: .topLeading
                )
                .accessibilityLabel(isEditingUserMessage ? "编辑上一条消息" : "消息")
                .accessibilityHint(textFieldAccessibilityHint)
#else
                TextField("发送消息给 OmniBot", text: $text, axis: .vertical)
                    .lineLimit(1...AppDesign.composerMaximumLines)
                    .focused(isFocused)
                    .textFieldStyle(.plain)
                    .font(AppDesign.composerTextFont)
                    .foregroundStyle(.primary)
                    .frame(
                        minHeight: AppDesign.composerTextLineHeight,
                        alignment: .topLeading
                    )
                    .disabled(isTextEntryDisabled)
                    .accessibilityLabel(isEditingUserMessage ? "编辑上一条消息" : "消息")
                    .accessibilityHint(textFieldAccessibilityHint)
#endif

                HStack(spacing: AppDesign.composerControlSpacing) {
                    ChatComposerAddMenu(
                        isDisabled: isBusy,
                        onImportAttachments: onImportAttachments,
                        onAddPhotos: onAddPhotos
                    )

                    Button(action: onToggleCommandToolbar) {
                        ComposerIconLabel(
                            title: "命令",
                            assetName: "ComposerCommand",
                            size: AppDesign.composerIconSize
                        )
                    }
                    .foregroundStyle(
                        isCommandToolbarPresented ? Color.accentColor : Color.secondary
                    )
                    .composerControlFrame()
                    .buttonStyle(.borderless)
                    .accessibilityLabel("命令")
                    .accessibilityValue(isCommandToolbarPresented ? "已展开" : "已收起")
                    .help("命令")

                    Spacer(minLength: AppDesign.standardSpacing)

                    ProviderModelMenu(
                        conversation: conversation,
                        isDisabled: isBusy
                    )

                    Button(action: onOpenTerminal) {
                        ComposerIconLabel(
                            title: "打开本地终端",
                            assetName: "ComposerTerminal",
                            size: AppDesign.composerTerminalIconSize
                        )
                    }
#if os(macOS)
                    .keyboardShortcut("j", modifiers: .command)
#endif
                    .foregroundStyle(.secondary)
                    .composerControlFrame()
                    .buttonStyle(.borderless)
                    .accessibilityLabel("打开本地终端")
#if os(macOS)
                    .help("本地终端（⌘J）")
#else
                    .help("本地终端")
#endif

                    ComposerSendButton(
                        isRunning: isRunning && !isEditingUserMessage,
                        canSend: canSend,
                        onSend: submit,
                        onCancel: onCancel
                    )
                }
            }
            .padding(
                .init(
                    top: AppDesign.composerContentTopPadding,
                    leading: AppDesign.composerContentHorizontalPadding,
                    bottom: AppDesign.composerContentBottomPadding,
                    trailing: AppDesign.composerContentHorizontalPadding
                )
            )
            .frame(minHeight: AppDesign.composerMinimumHeight)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: AppDesign.composerCornerRadius)
            )
            .overlay {
                ComposerGlassEdge()
                    .allowsHitTesting(false)
            }
            .background {
                Color.clear
                    .contentShape(.rect)
                    .gesture(TapGesture().onEnded(dismissFocus))
                    .accessibilityHidden(true)
            }
            .simultaneousGesture(
                TapGesture().onEnded(onInteraction)
            )

            if isBusy, !isRunning {
                Text(busyStatusMessage ?? busyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: AppDesign.composerMaximumWidth)
        .padding(.horizontal, AppDesign.composerHorizontalInset)
        .padding(.bottom, AppDesign.composerBottomPadding)
        .frame(maxWidth: .infinity)
        .onChange(of: focusRequestID) { _, _ in
            isFocused.wrappedValue = true
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedText.isEmpty
            && !isPreparingResend
            && (!isBusy || isEditingUserMessage)
    }

    private var isTextEntryDisabled: Bool {
        isPreparingResend || (isBusy && !isEditingUserMessage)
    }

    private var busyMessage: String {
        if isPreparingResend {
            return "正在准备编辑或重试…"
        }
        return "另一个会话正在运行，完成后即可发送。"
    }

    private var textFieldAccessibilityHint: String {
#if os(macOS)
        if isEditingUserMessage {
            return "修改后按 Enter 重新运行，按 Shift-Enter 换行"
        }
        return "输入要交给本地 Agent 的任务，按 Enter 发送，按 Shift-Enter 换行"
#else
        if isEditingUserMessage {
            return "修改后使用右侧发送按钮重新运行"
        }
        return "输入要交给本地 Agent 的任务，使用右侧发送按钮开始运行"
#endif
    }

    private func submit() {
        guard canSend else { return }
        onSend()
    }

    private func dismissFocus() {
        isFocused.wrappedValue = false
    }

}
