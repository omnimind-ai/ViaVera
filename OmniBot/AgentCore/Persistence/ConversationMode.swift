import Foundation

nonisolated public enum ConversationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case task
    case chat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .task: String(localized: "任务")
        case .chat: String(localized: "聊天")
        }
    }

    public var newConversationTitle: String {
        switch self {
        case .task: String(localized: "新任务")
        case .chat: String(localized: "新聊天")
        }
    }

    public var supportsTools: Bool { self == .task }
}
