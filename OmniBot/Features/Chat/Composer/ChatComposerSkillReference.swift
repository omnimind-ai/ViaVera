import Foundation

nonisolated struct ChatComposerSkillReference: Equatable, Sendable {
    let id: String
    let context: String

    static func nativeToolBuilder(editing toolID: UUID? = nil) -> Self {
        Self(
            id: "native-tool-builder",
            context: toolID.map { "修改已安装工具 tool_id=\($0.uuidString)，先读取最新工具包及 revision，保留用户数据。" }
                ?? "制作一个可以在「工具」页面直接使用的原生小工具。"
        )
    }

    func message(including request: String) -> String {
        "使用 $\(id)。\(context)\n\n用户需求：\n\(request)"
    }
}
