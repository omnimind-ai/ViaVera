import Foundation

nonisolated struct TOTPAccount: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let issuer: String
    let name: String
    let secret: Data
    let algorithm: TOTPAlgorithm
    let digits: Int
    let period: Int

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 200, issuer.count <= 200, (10...128).contains(secret.count),
              [6, 8].contains(digits), (1...3600).contains(period) else {
            throw NativeToolError("认证账户格式无效，请检查账户、密钥、位数和周期。")
        }
    }

    static func parse(_ input: String, name: String = "", issuer: String = "", algorithm: TOTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) throws -> TOTPAccount {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count <= 4096 else { throw NativeToolError("认证信息过长。") }
        if input.lowercased().hasPrefix("otpauth:") {
            guard let url = URLComponents(string: input), url.scheme?.lowercased() == "otpauth",
                  url.host?.lowercased() == "totp", url.user == nil, url.password == nil,
                  url.port == nil, url.fragment == nil else { throw NativeToolError("仅支持 otpauth://totp 认证链接。") }
            var parameters: [String: String] = [:]
            for item in url.queryItems ?? [] {
                guard parameters[item.name] == nil, let value = item.value else { throw NativeToolError("认证链接包含重复或空参数。") }
                parameters[item.name] = value
            }
            let label = String(url.path.drop(while: { $0 == "/" }))
            let parts = label.split(separator: ":", maxSplits: 1).map(String.init)
            let labelIssuer = parts.count == 2 ? parts[0] : ""
            if let declaredIssuer = parameters["issuer"], !labelIssuer.isEmpty, declaredIssuer != labelIssuer {
                throw NativeToolError("认证链接中的服务商信息不一致。")
            }
            guard let secret = parameters["secret"],
                  let algorithm = TOTPAlgorithm(rawValue: (parameters["algorithm"] ?? "SHA1").uppercased()),
                  let digits = Int(parameters["digits"] ?? "6"),
                  let period = Int(parameters["period"] ?? "30") else { throw NativeToolError("认证链接参数不受支持。") }
            let account = TOTPAccount(id: UUID(), issuer: parameters["issuer"] ?? labelIssuer,
                                      name: parts.last ?? "", secret: try decodeBase32(secret),
                                      algorithm: algorithm, digits: digits, period: period)
            try account.validate()
            return account
        }
        let account = TOTPAccount(id: UUID(), issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines),
                                  name: name.trimmingCharacters(in: .whitespacesAndNewlines), secret: try decodeBase32(input),
                                  algorithm: algorithm, digits: digits, period: period)
        try account.validate()
        return account
    }

    static func decodeBase32(_ input: String) throws -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        let normalized = input.uppercased().filter { !$0.isWhitespace }
        let unpadded = normalized.prefix(while: { $0 != "=" })
        let padding = normalized.count - unpadded.count
        guard !unpadded.isEmpty, normalized.dropFirst(unpadded.count).allSatisfy({ $0 == "=" }),
              padding == 0 || (normalized.count % 8 == 0 && padding < 8),
              [0, 2, 4, 5, 7].contains(unpadded.count % 8) else { throw NativeToolError("密钥不是有效的 Base32 编码。") }
        var buffer: UInt32 = 0
        var bits = 0
        var bytes: [UInt8] = []
        for character in unpadded.utf8 {
            guard let index = alphabet.firstIndex(of: character) else { throw NativeToolError("密钥不是有效的 Base32 编码。") }
            buffer = (buffer << 5) | UInt32(index)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 255))
                buffer &= (1 << bits) - 1
            }
        }
        guard buffer == 0 else { throw NativeToolError("密钥编码末尾无效。") }
        return Data(bytes)
    }
}
