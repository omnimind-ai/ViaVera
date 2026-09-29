#if os(macOS)
import Foundation

enum MacShortcutAction: String, CaseIterable, Identifiable {
    case newConversation, quickChat, searchConversations, openTools
    case goBack, goForward, focusComposer, terminal, commands, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .newConversation: String(localized: "新建会话")
        case .quickChat: String(localized: "快速聊天")
        case .searchConversations: String(localized: "搜索会话")
        case .openTools: String(localized: "我的工具")
        case .goBack: String(localized: "后退")
        case .goForward: String(localized: "前进")
        case .focusComposer: String(localized: "聚焦输入框")
        case .terminal: String(localized: "本地终端")
        case .commands: String(localized: "会话命令")
        case .settings: String(localized: "设置")
        }
    }

    var subtitle: String {
        switch self {
        case .newConversation: String(localized: "开始新的会话")
        case .quickChat: String(localized: "打开独立的快捷聊天窗口")
        case .searchConversations: String(localized: "在侧边栏中搜索历史会话")
        case .openTools: String(localized: "打开工具列表")
        case .goBack: String(localized: "返回上一个浏览的页面")
        case .goForward: String(localized: "前往下一个浏览的页面")
        case .focusComposer: String(localized: "在当前会话中开始输入")
        case .terminal: String(localized: "展开或收起当前会话的终端")
        case .commands: String(localized: "展开或收起会话命令栏")
        case .settings: String(localized: "打开软件设置")
        }
    }

    var defaultShortcut: AppKeyboardShortcut? {
        switch self {
        case .newConversation: .init(key: "n", modifiers: .command)
        case .quickChat: .init(key: "n", modifiers: [.option, .command])
        case .searchConversations: .init(key: "k", modifiers: .command)
        case .openTools: .init(key: "t", modifiers: [.shift, .command])
        case .goBack: .init(key: "[", modifiers: .command)
        case .goForward: .init(key: "]", modifiers: .command)
        case .focusComposer: .init(key: "l", modifiers: .command)
        case .terminal: .init(key: "j", modifiers: .command)
        case .commands: nil
        case .settings: .init(key: ",", modifiers: .command)
        }
    }
}
#endif
