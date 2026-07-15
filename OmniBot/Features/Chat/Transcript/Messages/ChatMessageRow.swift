import SwiftUI

struct ChatMessageRow: View {
    let presentation: ChatMessagePresentation
    let canEditAndRetryUserMessage: Bool
    let onEditUserMessage: () -> Void
    let onRetryUserMessage: () -> Void
    let onUserMessageContextMenuInteractionChanged: (Bool) -> Void

    var body: some View {
        switch presentation.message.role {
        case .user:
            UserMessageBubble(
                message: presentation.message,
                canEditAndRetry: canEditAndRetryUserMessage,
                onEdit: onEditUserMessage,
                onRetry: onRetryUserMessage,
                onContextMenuInteractionChanged:
                    onUserMessageContextMenuInteractionChanged
            )
        case .assistant:
            AssistantMessageView(
                message: presentation.message,
                content: presentation.content,
                reasoningContent: presentation.reasoningContent,
                isReasoningStreaming: presentation.isReasoningStreaming,
                toolCalls: presentation.toolCalls,
                turnUsage: presentation.turnUsage,
                showsStatus: presentation.showsStatus
            )
        case .tool:
            EmptyView()
        case .system:
            Text(presentation.message.content ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
