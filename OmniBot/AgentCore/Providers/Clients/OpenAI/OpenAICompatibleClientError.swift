import Foundation

nonisolated public enum OpenAICompatibleClientError: Error, Equatable, LocalizedError, Sendable,
    AgentRetryClassifying
{
    case unsupportedWireAPI(WireAPI)
    case invalidBaseURL(URL)
    case emptyAPIKey
    case streamingUnsupported
    case requestEncodingFailed(String)
    case invalidHTTPResponse
    case httpError(
        statusCode: Int,
        message: String,
        type: String?,
        code: String?,
        body: String?
    )
    case responseDecodingFailed(String)
    case responseTooLarge(maximumBytes: Int)
    case invalidUsage
    case credentialEchoInToolCall
    case emptyChoices
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedWireAPI(wireAPI):
            "The client does not support the '\(wireAPI.rawValue)' wire API."
        case let .invalidBaseURL(url):
            "Invalid provider base URL: \(url.absoluteString)"
        case .emptyAPIKey:
            "The provider API key is empty."
        case .streamingUnsupported:
            "Streaming responses are not supported by this client."
        case let .requestEncodingFailed(message):
            "The chat request could not be encoded: \(message)"
        case .invalidHTTPResponse:
            "The provider did not return an HTTP response."
        case let .httpError(statusCode, message, _, code, _):
            if let code {
                "Provider request failed (HTTP \(statusCode), \(code)): \(message)"
            } else {
                "Provider request failed (HTTP \(statusCode)): \(message)"
            }
        case let .responseDecodingFailed(message):
            "The provider response could not be decoded: \(message)"
        case let .responseTooLarge(maximumBytes):
            "The provider response exceeded the \(maximumBytes)-byte limit."
        case .invalidUsage:
            "The provider response contained negative token usage."
        case .credentialEchoInToolCall:
            "The provider response exposed credentials in a tool call and was rejected."
        case .emptyChoices:
            "The provider response did not contain a completion choice."
        case let .transport(message):
            "Provider network request failed: \(message)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .invalidHTTPResponse, .transport:
            true
        case let .httpError(statusCode, _, _, _, _):
            statusCode == 408
                || statusCode == 409
                || statusCode == 425
                || statusCode == 429
                || (500...599).contains(statusCode)
        case .unsupportedWireAPI,
             .invalidBaseURL,
             .emptyAPIKey,
             .streamingUnsupported,
             .requestEncodingFailed,
             .responseDecodingFailed,
             .responseTooLarge,
             .invalidUsage,
             .credentialEchoInToolCall,
             .emptyChoices:
            false
        }
    }

    var rejectsPromptCacheKey: Bool {
        guard case let .httpError(statusCode, message, type, code, body) = self,
              statusCode == 400 || statusCode == 422 else {
            return false
        }
        let detail = [message, type, code, body]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        guard detail.contains("prompt_cache_key") else { return false }
        return [
            "unknown", "unrecognized", "unsupported", "unexpected",
            "extra", "not permitted", "not allowed", "invalid parameter",
        ].contains { detail.contains($0) }
    }

    var rejectsAnthropicCacheControl: Bool {
        guard case let .httpError(statusCode, message, type, code, body) = self,
              statusCode == 400 || statusCode == 422 else {
            return false
        }
        let detail = [message, type, code, body]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        guard detail.contains("cache_control") else { return false }
        return [
            "unknown", "unrecognized", "unsupported", "unexpected",
            "extra", "not permitted", "not allowed", "invalid parameter",
        ].contains { detail.contains($0) }
    }
}
