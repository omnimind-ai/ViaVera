import Foundation

nonisolated enum TOTPTextImport {
    static let maximumBytes = 1_024 * 1_024
    static let maximumLinks = 1_000

    static func parseLink(_ link: String) throws -> TOTPAccount {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.lowercased().hasPrefix("otpauth://totp/") else {
            throw NativeToolError("仅支持 otpauth://totp/ 认证链接。")
        }
        return try TOTPAccount.parse(link)
    }

    static func parse(_ data: Data) throws -> [TOTPAccount] {
        guard data.count <= maximumBytes else { throw NativeToolError("TXT 文件不能超过 1 MB。") }
        let text = try NativeToolTextCodec.decode(data)
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var accounts: [TOTPAccount] = []
        for (index, line) in lines.enumerated() {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard accounts.count < maximumLinks else { throw NativeToolError("每次最多导入 1,000 条认证链接。") }
            do { accounts.append(try parseLink(line)) }
            catch {
                // Never include a link, secret, account name or parser payload in errors.
                throw NativeToolError("第 \(index + 1) 行不是有效的 TOTP 认证链接。请修正后重试，尚未导入任何账户。")
            }
        }
        guard !accounts.isEmpty else { throw NativeToolError("TXT 文件中没有认证链接。每行应为一条 otpauth://totp/ 链接。") }
        return accounts
    }

    static func read(_ url: URL) throws -> [TOTPAccount] {
        try parse(NativeToolSelectedFile.read(url, maximumBytes: maximumBytes))
    }
}
