import SwiftUI

struct AgentTurnProcessMessagesView: View {
    let messages: [ChatMessagePresentation]

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            ForEach(messages) { message in
                let startedTools = message.toolCalls.filter(\.wasStarted)
                if hasVisibleContent(message) || !startedTools.isEmpty {
                    AssistantMessageView(
                        message: message.message,
                        content: message.content,
                        reasoningContent: message.reasoningContent,
                        isReasoningStreaming: message.isReasoningStreaming,
                        toolCalls: startedTools,
                        turnUsage: nil,
                        showsStatus: message.showsStatus
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hasVisibleContent(_ message: ChatMessagePresentation) -> Bool {
        message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
            || message.reasoningContent?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
    }
}
