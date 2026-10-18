import Foundation

/// Bookkeeping updates (usage, sync dates, etc.) do not move the viewport.
struct TranscriptTailUpdate: Equatable {
    let messageID: UUID
    let payload: Data
    let status: MessageStatus

    init(_ message: MessageRecord) {
        messageID = message.id
        payload = message.payloadData
        status = message.status
    }
}
