import CryptoKit
import Foundation

nonisolated enum TOTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"

    func code(secret: Data, time: TimeInterval, digits: Int = 6, period: Int = 30) throws -> String {
        guard time.isFinite, time >= 0, [6, 8].contains(digits), period > 0,
              time / Double(period) < Double(UInt64.max) else { throw NativeToolError("验证码时间或参数无效。") }
        var counter = UInt64(time / Double(period)).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let key = SymmetricKey(data: secret)
        let digest: [UInt8]
        switch self {
        case .sha1: digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: digest = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: digest = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(digest[digest.count - 1] & 0x0f)
        let value = (UInt32(digest[offset] & 0x7f) << 24)
            | (UInt32(digest[offset + 1]) << 16)
            | (UInt32(digest[offset + 2]) << 8)
            | UInt32(digest[offset + 3])
        let modulus: UInt32 = digits == 6 ? 1_000_000 : 100_000_000
        return String(format: "%0*u", digits, value % modulus)
    }
}
