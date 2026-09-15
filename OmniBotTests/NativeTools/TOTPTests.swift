import Foundation
import Testing
@testable import Via_Vera

@Suite("TOTP standards and backup")
struct TOTPTests {
    @Test("RFC 6238 Appendix B vectors for SHA1, SHA256 and SHA512")
    func rfcVectors() throws {
        let times: [Double] = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000]
        let vectors: [(TOTPAlgorithm, String, [String])] = [
            (.sha1, "12345678901234567890", ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"]),
            (.sha256, "12345678901234567890123456789012", ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"]),
            (.sha512, "1234567890123456789012345678901234567890123456789012345678901234", ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"]),
        ]
        for (algorithm, secret, codes) in vectors {
            for (time, expected) in zip(times, codes) {
                #expect(try algorithm.code(secret: Data(secret.utf8), time: time, digits: 8) == expected)
            }
        }
        #expect(try TOTPAlgorithm.sha1.code(secret: Data("12345678901234567890".utf8), time: 1111111109, digits: 6) == "081804")
    }

    @Test("Parses encoded TOTP links and rejects ambiguous or unsupported parameters")
    func parser() throws {
        let account = try TOTPAccount.parse("otpauth://totp/Example:alice%40example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example&algorithm=SHA256&digits=8&period=60")
        #expect(account.name == "alice@example.com")
        #expect(account.secret == Data("12345678901234567890".utf8))
        #expect(account.algorithm == .sha256 && account.period == 60 && account.digits == 8)
        #expect(throws: NativeToolError.self) { try TOTPAccount.parse("otpauth://hotp/account?secret=GEZDGNBVGY3TQOJQ") }
        #expect(throws: NativeToolError.self) { try TOTPAccount.parse("otpauth://totp/account?secret=GEZDGNBVGY3TQOJQ&secret=GEZDGNBVGY3TQOJQ") }
        #expect(throws: NativeToolError.self) { try TOTPAccount.parse("otpauth://totp/One:account?secret=GEZDGNBVGY3TQOJQ&issuer=Two") }
        #expect(throws: NativeToolError.self) { try TOTPAccount.decodeBase32("INVALID0SECRET") }
    }

    @Test("Encrypted backups round-trip and reject incorrect passwords and tampering")
    func backups() throws {
        let account = try TOTPAccount.parse("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", name: "alice", issuer: "Example")
        let password = "long independent backup password"
        let data = try TOTPBackup.encrypt([account], password: password)
        #expect(!String(decoding: data, as: UTF8.self).contains("alice"))
        #expect(try TOTPBackup.decrypt(data, password: password) == [account])
        #expect(try TOTPBackup.encrypt([account], password: password) != data)
        #expect(throws: NativeToolError.self) { try TOTPBackup.decrypt(data, password: "incorrect password") }
        var envelope = try JSONDecoder().decode(AgentValue.self, from: data).objectValue!
        let ciphertextString = try #require(envelope["ciphertext"]?.stringValue)
        var ciphertext = try #require(Data(base64Encoded: ciphertextString))
        ciphertext[ciphertext.count - 1] ^= 1
        envelope["ciphertext"] = .string(ciphertext.base64EncodedString())
        let tampered = try JSONEncoder().encode(AgentValue.object(envelope))
        #expect(throws: NativeToolError.self) { try TOTPBackup.decrypt(tampered, password: password) }
    }
}
