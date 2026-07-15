import Foundation

nonisolated enum ChatCoordinatorError: LocalizedError {
    case conversationNotFound(UUID)
    case missingRetryMessage
    case retryMessageIsNotLatest
    case emptyRetryMessage
    case anotherConversationIsRunning
    case retryAlreadyInProgress
    case emptyContextSummary

    var errorDescription: String? {
        switch self {
        case let .conversationNotFound(identifier):
            "无法保存 Agent 事件：会话 \(identifier) 已不存在。"
        case .missingRetryMessage:
            "无法重试：会话中没有可恢复的用户消息。"
        case .retryMessageIsNotLatest:
            "只能编辑或重试最新一条用户消息。"
        case .emptyRetryMessage:
            "编辑后的消息不能为空。"
        case .anotherConversationIsRunning:
            "另一个会话正在运行，请等待其完成后再重试。"
        case .retryAlreadyInProgress:
            "正在处理上一项编辑或重试操作。"
        case .emptyContextSummary:
            "模型没有返回可用的上下文摘要。"
        }
    }
}
