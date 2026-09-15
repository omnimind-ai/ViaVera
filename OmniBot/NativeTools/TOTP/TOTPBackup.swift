import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum TOTPBackup {
    private struct Envelope: Codable {
        let version: Int
        let iterations: UInt32
        let salt: Data
        let ciphertext: Data
    }
    private static let iterations: UInt32 = 600_000

    static func encrypt(_ accounts: [TOTPAccount], password: String) throws -> Data {
        guard password.count >= 12, password.utf8.count <= 1024 else { throw NativeToolError("备份密码须为 12 至 1024 个字符。") }
        try TOTPKeychainVault.validate(accounts)
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw NativeToolError("无法生成备份随机数。") }
        let key = try derive(password, salt: salt, iterations: iterations)
        let encrypted = try AES.GCM.seal(JSONEncoder().encode(accounts), using: key, authenticating: Data("OmniBot-TOTP-v1".utf8))
        guard let ciphertext = encrypted.combined else { throw NativeToolError("加密备份失败。") }
        return try JSONEncoder().encode(Envelope(version: 1, iterations: iterations, salt: salt, ciphertext: ciphertext))
    }

    static func decrypt(_ data: Data, password: String) throws -> [TOTPAccount] {
        guard data.count <= 512 * 1024, password.utf8.count <= 1024 else { throw NativeToolError("备份文件或密码过长。") }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1, envelope.iterations == iterations, envelope.salt.count == 16 else {
                throw NativeToolError("不支持的备份格式。")
            }
            let key = try derive(password, salt: envelope.salt, iterations: envelope.iterations)
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.ciphertext), using: key, authenticating: Data("OmniBot-TOTP-v1".utf8))
            let accounts = try JSONDecoder().decode([TOTPAccount].self, from: plaintext)
            try TOTPKeychainVault.validate(accounts)
            return accounts
        } catch { throw NativeToolError("备份密码错误，或文件已损坏/格式不受支持。") }
    }

    private static func derive(_ password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { keyBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordBytes.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                                        passwordBytes.count, saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                        keyBuffer.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        guard status == kCCSuccess else { throw NativeToolError("备份密钥派生失败。") }
        return SymmetricKey(data: key)
    }
}
