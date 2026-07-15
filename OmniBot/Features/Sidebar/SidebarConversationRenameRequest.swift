import Foundation

struct SidebarConversationRenameRequest: Equatable {
    let requestID = UUID()
    let conversationID: UUID
}
