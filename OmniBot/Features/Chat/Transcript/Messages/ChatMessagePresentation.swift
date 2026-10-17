import Foundation

struct ChatMessagePresentation: Identifiable {
    let message: MessageRecord
    let content: String?
    let reasoningContent: String?
    let isReasoningStreaming: Bool
    let toolCalls: [ToolCallPresentation]
    let showsStatus: Bool
    var completion: ResponseCompletionPresentation? = nil

    var id: UUID {
        message.id
    }
}
