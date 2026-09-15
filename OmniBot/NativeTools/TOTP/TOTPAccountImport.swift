import Foundation

nonisolated enum TOTPAccountImport {
    /// Prepare and validate the whole batch before the vault performs a single write.
    static func merging(_ additions: [TOTPAccount], into existing: [TOTPAccount]) throws -> TOTPAccountImportResult {
        try TOTPKeychainVault.validate(existing)
        var accounts = existing
        var duplicates = 0
        for account in additions {
            try account.validate()
            if accounts.contains(where: {
                $0.issuer == account.issuer && $0.name == account.name && $0.secret == account.secret
                    && $0.algorithm == account.algorithm && $0.digits == account.digits && $0.period == account.period
            }) {
                duplicates += 1
                continue
            }
            guard accounts.count < 200 else { throw NativeToolError("导入后超过 200 个账户上限，未保存本次导入。") }
            accounts.append(TOTPAccount(
                id: UUID(), issuer: account.issuer, name: account.name, secret: account.secret,
                algorithm: account.algorithm, digits: account.digits, period: account.period
            ))
        }
        return TOTPAccountImportResult(accounts: accounts, importedCount: accounts.count - existing.count, duplicateCount: duplicates)
    }
}
