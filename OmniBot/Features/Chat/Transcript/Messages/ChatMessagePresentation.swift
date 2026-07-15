import Foundation

struct ChatMessagePresentation: Identifiable {
    let message: MessageRecord
    let content: String?
    let reasoningContent: String?
    let isReasoningStreaming: Bool
    let toolCalls: [ToolCallPresentation]
    let turnUsage: TurnUsagePresentation?
    let showsStatus: Bool

    var id: UUID {
        message.id
    }
}
