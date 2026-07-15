import Foundation

nonisolated public enum ProviderStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidIdentifier
    case invalidName
    case invalidBaseURL
    case unsupportedWireAPI(ProviderProtocolType, WireAPI)
    case insecureBaseURL
    case baseURLCredentialsNotAllowed
    case baseURLFragmentNotAllowed
    case secretQueryItemNotAllowed(String)
    case duplicateProviderIdentifier(String)
    case duplicateModelIdentifier(String)
    case invalidModelLimits(String)
    case invalidHeaderName(String)
    case invalidHeaderValue(String)
    case duplicateHeaderName(String)
    case routingHeaderNotAllowed(String)
    case secretHeaderNotAllowed(String)
    case metadataLimitExceeded(String)
    case storeFileNotRegular
    case storeFileTooLarge(Int)
    case providerNotFound(String)
    case invalidProviderOrder
    case corruptedStore(String)
    case persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            "Provider identifier cannot be empty."
        case .invalidName:
            "Provider name cannot be empty."
        case .invalidBaseURL:
            "Provider base URL must be a valid URL with a host."
        case let .unsupportedWireAPI(protocolType, wireAPI):
            "The '\(protocolType.rawValue)' protocol does not support the '\(wireAPI.rawValue)' wire API."
        case .insecureBaseURL:
            "Provider base URL must use HTTPS. HTTP is allowed only for loopback hosts."
        case .baseURLCredentialsNotAllowed:
            "Provider base URL cannot contain a username or password."
        case .baseURLFragmentNotAllowed:
            "Provider base URL cannot contain a fragment."
        case let .secretQueryItemNotAllowed(name):
            "Provider base URL query item '\(name)' may contain a secret and is not allowed."
        case let .duplicateProviderIdentifier(identifier):
            "Provider identifier '\(identifier)' occurs more than once."
        case let .duplicateModelIdentifier(identifier):
            "Model identifier '\(identifier)' occurs more than once."
        case let .invalidModelLimits(identifier):
            "Model '\(identifier)' must have positive token limits, and maximum output tokens cannot exceed its context window."
        case let .invalidHeaderName(header):
            "Header name '\(header)' is not a valid HTTP field name."
        case let .invalidHeaderValue(header):
            "Header '\(header)' contains a prohibited control character."
        case let .duplicateHeaderName(header):
            "Header '\(header)' occurs more than once when compared case-insensitively."
        case let .routingHeaderNotAllowed(header):
            "Routing header '\(header)' is controlled by the HTTP stack and is not allowed."
        case let .secretHeaderNotAllowed(header):
            "Header '\(header)' may contain a secret and must be stored in Keychain instead."
        case let .metadataLimitExceeded(message):
            "Provider metadata exceeds its safety limit: \(message)"
        case .storeFileNotRegular:
            "The provider store must be a regular file and symbolic links are not allowed."
        case let .storeFileTooLarge(maximumByteCount):
            "The provider store exceeds the \(maximumByteCount)-byte safety limit."
        case let .providerNotFound(identifier):
            "Provider '\(identifier)' was not found."
        case .invalidProviderOrder:
            "Provider order must contain every configured provider exactly once."
        case let .corruptedStore(message):
            "The provider store could not be decoded: \(message)"
        case let .persistenceFailed(message):
            "The provider store could not be saved: \(message)"
        }
    }
}
