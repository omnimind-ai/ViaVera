import Foundation

enum ChatTimelineEntry: Identifiable {
    case message(ChatMessagePresentation)
    case agentTurn(AgentTurnPresentation)

    var id: String {
        switch self {
        case let .message(message):
            "message:\(message.id.uuidString)"
        case let .agentTurn(turn):
            "agent-turn:\(turn.id.uuidString)"
        }
    }

    var message: ChatMessagePresentation? {
        guard case let .message(message) = self else { return nil }
        return message
    }

    var agentTurn: AgentTurnPresentation? {
        guard case let .agentTurn(turn) = self else { return nil }
        return turn
    }
}
