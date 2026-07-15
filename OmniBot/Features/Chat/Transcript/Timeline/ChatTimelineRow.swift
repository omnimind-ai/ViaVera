import SwiftUI

struct ChatTimelineRow: View {
    let entry: ChatTimelineEntry
    let latestUserMessageID: UUID?
    let isBusy: Bool
    let isRunning: Bool
    let isAgentTurnManuallyExpanded: Bool
    let onEditUserMessage: (MessageRecord) -> Void
    let onRetryUserMessage: (MessageRecord) -> Void
    let onUserMessageContextMenuInteractionChanged: (Bool) -> Void
    let onToggleAgentTurn: (UUID) -> Void

    var body: some View {
        switch entry {
        case let .message(message):
            ChatMessageRow(
                presentation: message,
                canEditAndRetryUserMessage:
                    message.id == latestUserMessageID
                    && (!isBusy || isRunning),
                onEditUserMessage: {
                    onEditUserMessage(message.message)
                },
                onRetryUserMessage: {
                    onRetryUserMessage(message.message)
                },
                onUserMessageContextMenuInteractionChanged:
                    onUserMessageContextMenuInteractionChanged
            )
        case let .agentTurn(turn):
            AgentTurnView(
                turn: turn,
                isManuallyExpanded: isAgentTurnManuallyExpanded,
                onToggleExpanded: { onToggleAgentTurn(turn.id) }
            )
        }
    }
}
