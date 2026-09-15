import Foundation
import LocalAuthentication
import Security

/// Separate service and account namespace from provider keys and all tool JSON.
nonisolated struct TOTPKeychainVault {
    let toolID: UUID

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "OmniBot").native-tools.totp",
         kSecAttrAccount as String: toolID.uuidString,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    func load(context: LAContext) throws -> [TOTPAccount] {
        context.interactionNotAllowed = true
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 256 * 1024 else {
            throw NativeToolError("无法读取验证码账户，请重新解锁。")
        }
        let accounts = try JSONDecoder().decode([TOTPAccount].self, from: data)
        try Self.validate(accounts)
        return accounts
    }

    func add(_ additions: [TOTPAccount], context: LAContext) throws -> [TOTPAccount] {
        var accounts = try load(context: context)
        for account in additions {
            try account.validate()
            guard !accounts.contains(where: { $0.issuer == account.issuer && $0.name == account.name && $0.secret == account.secret && $0.algorithm == account.algorithm && $0.digits == account.digits && $0.period == account.period }) else { continue }
            accounts.append(TOTPAccount(id: UUID(), issuer: account.issuer, name: account.name, secret: account.secret, algorithm: account.algorithm, digits: account.digits, period: account.period))
        }
        try save(accounts, context: context)
        return accounts
    }

    func remove(_ id: UUID, context: LAContext) throws -> [TOTPAccount] {
        let accounts = try load(context: context).filter { $0.id != id }
        try save(accounts, context: context)
        return accounts
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NativeToolError("无法删除验证码账户，请解锁设备后重试。") }
    }

    private func save(_ accounts: [TOTPAccount], context: LAContext) throws {
        context.interactionNotAllowed = true
        try Self.validate(accounts)
        let data = try JSONEncoder().encode(accounts)
        var request = query
        request[kSecUseAuthenticationContext as String] = context
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw NativeToolError("验证码账户未能保存，请重新解锁后重试。") }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
            throw NativeToolError("无法建立密钥访问保护。")
        }
        var attributes = query
        attributes[kSecAttrAccessControl as String] = access
        attributes[kSecUseAuthenticationContext as String] = context
        attributes[kSecValueData as String] = data
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw NativeToolError("验证码账户未能保存。请确认设备已设置解锁密码。") }
    }

    static func validate(_ accounts: [TOTPAccount]) throws {
        guard accounts.count <= 200, Set(accounts.map(\.id)).count == accounts.count else { throw NativeToolError("账户数量超过上限或 ID 重复。") }
        for account in accounts { try account.validate() }
    }
}
