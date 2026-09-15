import Foundation
import Testing
@testable import Via_Vera

@Suite("TOTP camera payloads and text import")
struct TOTPImportTests {
    private let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    private func link(_ name: String = "alice") -> String {
        "otpauth://totp/Example:\(name)?secret=\(secret)&issuer=Example"
    }

    @Test("TXT supports UTF-8, BOMs, Windows and Unix newlines, blank lines and surrounding spaces")
    func textFormats() throws {
        let contents = " \r\n\t\(link())  \r\n\r\n\(link("bob"))\n"
        let encodings: [(String.Encoding, Data)] = [
            (.utf8, Data()), (.utf8, Data([0xEF, 0xBB, 0xBF])),
            (.utf16LittleEndian, Data([0xFF, 0xFE])), (.utf16BigEndian, Data([0xFE, 0xFF])),
        ]
        for (encoding, bom) in encodings {
            let accounts = try TOTPTextImport.parse(bom + #require(contents.data(using: encoding)))
            #expect(accounts.map(\.name) == ["alice", "bob"])
            #expect(accounts.allSatisfy { $0.issuer == "Example" && $0.secret == Data("12345678901234567890".utf8) })
        }
    }

    @Test("A malformed line aborts the entire parse and reports its physical line without revealing secrets")
    func invalidLine() throws {
        let text = "\(link())\r\n\r\notpauth://totp/private-account?secret=PRIVATE-SECRET\r\n\(link("bob"))"
        do {
            _ = try TOTPTextImport.parse(Data(text.utf8))
            Issue.record("A malformed batch should not produce any accounts")
        } catch {
            #expect(error.localizedDescription.contains("第 3 行"))
            #expect(!error.localizedDescription.contains("PRIVATE-SECRET"))
            #expect(!error.localizedDescription.contains("private-account"))
            #expect(!error.localizedDescription.contains("otpauth"))
        }
        #expect(throws: NativeToolError.self) { try TOTPTextImport.parse(Data("\n \r\n".utf8)) }
        #expect(throws: NativeToolError.self) { try TOTPTextImport.parse(Data([0xFF, 0x00, 0xC0])) }
        #expect(throws: NativeToolError.self) { try TOTPTextImport.parse(Data(secret.utf8)) }
    }

    @Test("Input size and link count are bounded and a chosen TXT file is read through the production loader")
    func fileLimits() throws {
        #expect(throws: NativeToolError.self) { try TOTPTextImport.parse(Data(repeating: 32, count: TOTPTextImport.maximumBytes + 1)) }
        let tooMany = Array(repeating: link(), count: TOTPTextImport.maximumLinks + 1).joined(separator: "\n")
        #expect(throws: NativeToolError.self) { try TOTPTextImport.parse(Data(tooMany.utf8)) }
        let file = FileManager.default.temporaryDirectory.appending(path: "totp-import-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("\(link())\n\(link("bob"))".utf8).write(to: file)
        #expect(try TOTPTextImport.read(file).map(\.name) == ["alice", "bob"])
    }

    @Test("Batch merge skips duplicates in both the file and vault while preserving existing account identities")
    func duplicates() throws {
        let alice = try TOTPAccount.parse(link())
        let bob = try TOTPAccount.parse(link("bob"))
        let result = try TOTPAccountImport.merging([alice, bob, bob], into: [alice])
        #expect(result.importedCount == 1)
        #expect(result.duplicateCount == 2)
        #expect(result.accounts.count == 2)
        #expect(result.accounts[0] == alice)
        #expect(result.accounts[1].id != bob.id)
        let repeated = try TOTPAccountImport.merging([alice, bob], into: result.accounts)
        #expect(repeated.importedCount == 0 && repeated.duplicateCount == 2)
        #expect(repeated.accounts == result.accounts)
        let differentPeriod = try TOTPAccount.parse(link() + "&period=60")
        #expect(try TOTPAccountImport.merging([differentPeriod], into: [alice]).importedCount == 1)
    }

    @Test("Batch capacity and validation failures cannot mutate the original account list")
    func atomicValidation() throws {
        let existing = try (0..<200).map { try TOTPAccount.parse(link("account\($0)")) }
        let fresh = try TOTPAccount.parse(link("fresh"))
        #expect(throws: NativeToolError.self) { try TOTPAccountImport.merging([fresh], into: existing) }
        #expect(existing.count == 200)
        #expect(try TOTPAccountImport.merging([existing[0]], into: existing).duplicateCount == 1)
        let invalid = TOTPAccount(id: UUID(), issuer: "", name: "", secret: Data(), algorithm: .sha1, digits: 6, period: 30)
        #expect(throws: NativeToolError.self) { try TOTPAccountImport.merging([fresh, invalid], into: []) }
    }

    @Test("Shared camera/photo payloads accept arbitrary QR content; OTP interpretation is a separate capability")
    func qrPayloads() throws {
        #expect(try NativeToolQRCodePayload.extract([link(), link()]) == link())
        #expect(try NativeToolQRCodePayload.extract(["https://example.com"]) == "https://example.com")
        #expect(throws: NativeToolError.self) { try NativeToolQRCodePayload.extract([]) }
        #expect(throws: NativeToolError.self) { try NativeToolQRCodePayload.extract([link(), link("bob")]) }
        let payload = try NativeToolQRCodePayload.extract(["otpauth://hotp/alice?secret=\(secret)"])
        #expect(throws: NativeToolError.self) { try TOTPTextImport.parseLink(payload) }
    }
}
