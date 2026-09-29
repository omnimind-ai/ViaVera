import Foundation

nonisolated struct TOTPAccountImportResult: Sendable {
    let accounts: [TOTPAccount]
    let importedCount: Int
    let duplicateCount: Int

    var summary: String {
        if duplicateCount > 0 {
            String(localized: "已导入 \(importedCount) 个账户，跳过 \(duplicateCount) 个重复账户。")
        } else {
            String(localized: "已导入 \(importedCount) 个账户。")
        }
    }
}
