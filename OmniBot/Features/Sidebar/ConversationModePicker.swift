import SwiftUI

struct ConversationModePicker: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedMode = ConversationMode.task
#if os(macOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#endif

    var body: some View {
        Group {
#if os(macOS)
            HStack(spacing: 0) {
                ForEach(ConversationMode.allCases) { mode in
                    Button {
                        selectMode(mode)
                    } label: {
                        Text(mode.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(selectedMode == mode ? .primary : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                }
            }
            .background {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.background)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .frame(width: geometry.size.width / 2)
                        .offset(x: selectedMode == .task ? 0 : geometry.size.width / 2)
                }
                .allowsHitTesting(false)
            }
            .padding(3)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: .capsule)
            .accessibilityElement(children: .contain)
#else
            Picker("会话模式", selection: $selectedMode) {
                Text(ConversationMode.task.title).tag(ConversationMode.task)
                Text(ConversationMode.chat.title).tag(ConversationMode.chat)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
#endif
        }
        .accessibilityLabel("会话模式")
        .accessibilityHint("切换任务和聊天，分别保留各自的会话")
        .onChange(of: appModel.conversationMode, initial: true) { _, mode in
            synchronizeSelection(mode)
        }
#if !os(macOS)
        .onChange(of: selectedMode) { _, mode in
            guard mode != appModel.conversationMode else { return }
            appModel.selectConversationMode(mode)
        }
#endif
    }

    private func synchronizeSelection(_ mode: ConversationMode) {
        // The picker already changed in the shared animation transaction.
        // Do not replace that transaction when its model update is observed.
        guard selectedMode != mode else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { selectedMode = mode }
    }

#if os(macOS)
    private func selectMode(_ mode: ConversationMode) {
        guard mode != selectedMode else { return }
        // One transaction keeps the persistent slider, sidebar, and transcript
        // in sync, including when a second click interrupts the transition.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
            selectedMode = mode
            appModel.selectConversationMode(mode)
        }
    }
#endif
}
