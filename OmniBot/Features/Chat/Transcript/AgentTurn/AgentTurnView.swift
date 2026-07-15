import SwiftUI

struct AgentTurnView: View {
    let turn: AgentTurnPresentation
    let isManuallyExpanded: Bool
    let onToggleExpanded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            if turn.isActive {
                AgentTurnProcessMessagesView(messages: turn.processMessages)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: onToggleExpanded) {
                        HStack(spacing: AppDesign.transcriptStatusInlineSpacing) {
                            Text(summaryTitle)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isManuallyExpanded ? 90 : 0))
                                .animation(
                                    reduceMotion ? nil : .easeInOut(duration: 0.26),
                                    value: isManuallyExpanded
                                )
                                .accessibilityHidden(true)
                        }
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)
                        .frame(minHeight: AppDesign.transcriptStatusMinimumHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, AppDesign.transcriptStatusVerticalPadding)
                    .accessibilityLabel(
                        isManuallyExpanded ? "收起 Agent 执行过程" : "展开 Agent 执行过程"
                    )

                    AgentTurnProcessRevealView(
                        messages: turn.processMessages,
                        isExpanded: isManuallyExpanded
                    )
                }
            }

            ForEach(turn.visibleMessages) { message in
                AssistantMessageView(
                    message: message.message,
                    content: message.content,
                    reasoningContent: message.reasoningContent,
                    isReasoningStreaming: message.isReasoningStreaming,
                    toolCalls: message.toolCalls,
                    turnUsage: nil,
                    showsStatus: message.showsStatus
                )
            }

            if let usage = turn.turnUsage {
                MessageUsageCapsule(
                    contextTokens: usage.contextTokens,
                    inputTokens: usage.inputTokens,
                    outputTokens: usage.outputTokens,
                    cachedTokens: usage.cachedTokens
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryTitle: String {
        turn.elapsedLabel.isEmpty ? "已处理" : "已处理  \(turn.elapsedLabel)"
    }
}
