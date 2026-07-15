import Foundation
import Security

nonisolated public enum KeychainAPIKeyStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidProviderIdentifier
    case emptyAPIKey
    case emptyEndpointBinding
    case invalidStoredData
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidProviderIdentifier:
            "Provider identifier cannot be empty."
        case .emptyAPIKey:
            "API key cannot be empty."
        case .emptyEndpointBinding:
            "Provider endpoint binding cannot be empty."
        case .invalidStoredData:
            "The provider credential data stored in Keychain is not valid UTF-8."
        case let .unexpectedStatus(status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain returned status \(status)."
        }
    }
}

/// Generic-password Keychain storage for provider API keys.
///
/// The implementation is safe to call from any actor. Security.framework owns
/// synchronization for `SecItem` operations.
nonisolated public final class KeychainAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    public let service: String
    public let accessGroup: String?

    public init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "OmniBot").provider-api-keys",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func saveAPIKey(_ apiKey: String, for providerID: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainAPIKeyStoreError.emptyAPIKey
        }
        try saveValue(apiKey, account: apiKeyAccount(for: providerID))
    }

    public func apiKey(for providerID: String) throws -> String? {
        try value(account: apiKeyAccount(for: providerID))
    }

    public func deleteAPIKey(for providerID: String) throws {
        try deleteValue(account: apiKeyAccount(for: providerID))
    }

    public func saveEndpointBinding(
        _ endpointIdentity: String,
        for providerID: String
    ) throws {
        guard !endpointIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeychainAPIKeyStoreError.emptyEndpointBinding
        }
        try saveValue(endpointIdentity, account: endpointBindingAccount(for: providerID))
    }

    public func endpointBinding(for providerID: String) throws -> String? {
        try value(account: endpointBindingAccount(for: providerID))
    }

    public func deleteEndpointBinding(for providerID: String) throws {
        try deleteValue(account: endpointBindingAccount(for: providerID))
    }

    private func saveValue(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainAPIKeyStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainAPIKeyStoreError.unexpectedStatus(updateStatus)
        }
    }

    private func value(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainAPIKeyStoreError.invalidStoredData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainAPIKeyStoreError.unexpectedStatus(status)
        }
    }

    private func deleteValue(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAPIKeyStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }

    private func apiKeyAccount(for providerID: String) throws -> String {
        "provider.\(try validatedIdentifier(providerID))"
    }

    private func endpointBindingAccount(for providerID: String) throws -> String {
        "endpoint-binding.\(try validatedIdentifier(providerID))"
    }

    private func validatedIdentifier(_ providerID: String) throws -> String {
        let identifier = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            throw KeychainAPIKeyStoreError.invalidProviderIdentifier
        }
        return identifier
    }
}
