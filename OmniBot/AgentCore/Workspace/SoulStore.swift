import Foundation

public actor SoulStore {
    public static let defaultSoul = """
    # SOUL

    你是小万，一个值得信赖的智能助手。优先把事情做完，再用简洁、温暖且可执行的方式说明结果。

    - 以事实和工具结果为依据，不虚构已经执行或验证的动作。
    - 涉及隐私、删除、付费、凭据或向外部发送内容时，先明确确认。
    - 不泄露密钥，不执行破坏性命令，不绕过系统安全边界。
    - 值得跨会话保留的信息及时写入每日记忆；稳定结论再写入长期记忆。
    - 只有用户明确同意时才修改 SOUL，并说明修改了什么。
    """

    public static let defaultChatSoul = """
    # CHAT SOUL

    你是小万，一个温暖、真诚、善于倾听的聊天伙伴。

    - 自然地回应用户，保持清晰、友善的表达，尊重不同观点。
    - 根据对话需要调整回答的长短；简单的问题简洁回答，复杂的话题耐心说明。
    - 认真理解用户的感受和意图，需要时提出有帮助的问题。
    - 如实说明不确定之处，不编造事实或经历。
    """

    private let paths: WorkspacePaths

    public init(paths: WorkspacePaths) {
        self.paths = paths
    }

    public func load(mode: ConversationMode = .task) throws -> String {
        try prepare(mode: mode)
        let file = file(for: mode)
        let defaultContent = mode == .chat ? Self.defaultChatSoul : Self.defaultSoul
        guard FileManager.default.fileExists(atPath: file.path) else {
            try defaultContent.write(to: file, atomically: true, encoding: .utf8)
            return defaultContent
        }
        return try String(contentsOf: file, encoding: .utf8)
    }

    public func save(_ soul: String, mode: ConversationMode = .task) throws {
        try prepare(mode: mode)
        let normalized = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        // Defaults are seeded only for a missing file; an empty editor is an intentional value.
        let value = normalized.isEmpty ? "" : normalized + "\n"
        try value.write(to: file(for: mode), atomically: true, encoding: .utf8)
    }

    private func prepare(mode: ConversationMode) throws {
        if mode == .chat {
            try paths.prepareHostConfiguration()
        } else {
            try paths.prepare()
        }
    }

    private func file(for mode: ConversationMode) -> URL {
        mode == .chat ? paths.chatSoulFile : paths.soulFile
    }
}
