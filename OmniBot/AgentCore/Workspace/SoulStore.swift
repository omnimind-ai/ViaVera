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

    private let paths: WorkspacePaths

    public init(paths: WorkspacePaths) {
        self.paths = paths
    }

    public func load() throws -> String {
        try paths.prepare()
        guard FileManager.default.fileExists(atPath: paths.soulFile.path) else {
            try Self.defaultSoul.write(to: paths.soulFile, atomically: true, encoding: .utf8)
            return Self.defaultSoul
        }
        return try String(contentsOf: paths.soulFile, encoding: .utf8)
    }

    public func save(_ soul: String) throws {
        try paths.prepare()
        let normalized = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        // Defaults are seeded only for a missing file; an empty editor is an intentional value.
        let value = normalized.isEmpty ? "" : normalized + "\n"
        try value.write(to: paths.soulFile, atomically: true, encoding: .utf8)
    }
}
