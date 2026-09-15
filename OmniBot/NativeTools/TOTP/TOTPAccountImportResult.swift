import Foundation

nonisolated struct TOTPAccountImportResult: Sendable {
    let accounts: [TOTPAccount]
    let importedCount: Int
    let duplicateCount: Int

    var summary: String {
        "已导入 \(importedCount) 个账户" + (duplicateCount > 0 ? "，跳过 \(duplicateCount) 个重复账户。" : "。")
    }
}
