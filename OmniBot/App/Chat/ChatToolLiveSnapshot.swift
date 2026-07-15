import Foundation

struct ChatToolLiveSnapshot: Equatable {
    let runID: UUID
    let conversationID: UUID
    let assistantMessageIDs: Set<UUID>
    let activeAssistantMessageID: UUID?
    let activeCallID: String?
    let terminalOutput: String
}
