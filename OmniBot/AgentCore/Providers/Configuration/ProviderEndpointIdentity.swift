import CryptoKit
import Foundation

/// Canonical identity stored beside a provider credential in Keychain.
///
/// Provider metadata is intentionally non-secret JSON and can be edited outside
/// the app. Binding the credential to this independently protected identity
/// prevents a profile ID from being reused to send a saved key to another host
/// or gateway-routing context.
nonisolated enum ProviderEndpointIdentity {
    static func canonical(for profile: ProviderProfile) -> String {
        let endpoint = (try? ProviderEndpointResolver.requestURL(for: profile))
            ?? profile.baseURL
        let canonicalEndpoint: String
        if var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            if (components.scheme == "https" && components.port == 443)
                || (components.scheme == "http" && components.port == 80) {
                components.port = nil
            }
            components.fragment = nil
            while components.percentEncodedPath.count > 1,
                  components.percentEncodedPath.hasSuffix("/") {
                components.percentEncodedPath.removeLast()
            }
            canonicalEndpoint = components.string ?? endpoint.absoluteString
        } else {
            canonicalEndpoint = endpoint.absoluteString
        }

        // Header names are case-insensitive on the wire. ProviderStore rejects
        // duplicate normalized names, so sorting produces one deterministic
        // representation of every header that can affect gateway routing.
        let headers = profile.defaultHeaders
            .map { (name: $0.key.lowercased(), value: $0.value) }
            .sorted {
                if $0.name == $1.name {
                    return $0.value < $1.value
                }
                return $0.name < $1.name
            }

        // Length-prefix every UTF-8 field before hashing. This avoids delimiter
        // collisions even when header values contain arbitrary punctuation.
        var payload = Data()
        // Preserve the pre-protocol identity for existing OpenAI-compatible
        // Chat Completions profiles. Their Keychain binding must remain valid
        // after decoding the new protocol field with its legacy default.
        if profile.protocolType != .openAICompatible {
            append(profile.protocolType.rawValue, to: &payload)
        }
        append(profile.wireAPI.rawValue, to: &payload)
        append(canonicalEndpoint, to: &payload)
        append(String(headers.count), to: &payload)
        for header in headers {
            append(header.name, to: &payload)
            append(header.value, to: &payload)
        }
        return "sha256:\(Data(SHA256.hash(data: payload)).base64EncodedString())"
    }

    private static func append(_ value: String, to payload: inout Data) {
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        payload.append(bytes)
    }
}
