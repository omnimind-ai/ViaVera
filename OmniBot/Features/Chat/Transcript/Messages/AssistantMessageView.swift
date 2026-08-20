import SwiftUI

struct AssistantMessageView: View {
    let message: MessageRecord
    let content: String?
    let reasoningContent: String?
    let isReasoningStreaming: Bool
    let toolCalls: [ToolCallPresentation]
    let turnUsage: TurnUsagePresentation?
    let showsStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            if let visibleReasoningContent {
                ReasoningDisclosureView(
                    text: visibleReasoningContent,
                    isStreaming: isReasoningStreaming,
                    autoCollapse: !isReasoningStreaming,
                    startedAt: message.createdAt,
                    updatedAt: message.updatedAt
                )
            }

            if hasVisibleContent {
                SmoothStreamingText(
                    text: content ?? "",
                    isStreaming: message.status == .streaming
                )
            } else if visibleReasoningContent == nil,
                      message.status == .pending || message.status == .streaming {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("OmniBot 正在生成回复")
            }

            ForEach(toolCalls) { tool in
                ToolCallCapsule(tool: tool)
            }

            if showsStatus,
               message.status == .failed || message.status == .interrupted {
                Label(
                    message.status == .failed ? "回复生成失败" : "回复已中断",
                    systemImage: message.status == .failed
                        ? "exclamationmark.circle"
                        : "stop.circle"
                )
                .font(.caption)
                .foregroundStyle(message.status == .failed ? Color.red : Color.secondary)
            }

            if let turnUsage {
                MessageUsageCapsule(
                    contextTokens: turnUsage.contextTokens,
                    inputTokens: turnUsage.inputTokens,
                    outputTokens: turnUsage.outputTokens,
                    cachedTokens: turnUsage.cachedTokens,
                    cacheCreationTokens: turnUsage.cacheCreationTokens,
                    cacheHitPercentage: turnUsage.cacheHitPercentage
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasVisibleContent: Bool {
        content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var visibleReasoningContent: String? {
        guard let reasoningContent,
              !reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return reasoningContent
    }
}
