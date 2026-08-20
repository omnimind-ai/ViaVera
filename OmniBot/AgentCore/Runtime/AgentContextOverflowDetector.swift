import Foundation

nonisolated enum AgentContextOverflowDetector {
    private static let overflowPatterns = [
        "prompt is too long",
        "request_too_large",
        "input is too long for requested model",
        "exceeds the context window",
        "exceeds context window",
        "maximum context length",
        "input token count",
        "maximum prompt length",
        "reduce the length of the messages",
        "maximum allowed input length",
        "available context size",
        "greater than the context length",
        "model_context_window_exceeded",
        "context_length_exceeded",
        "context length exceeded",
        "too many tokens",
        "token limit exceeded",
    ]

    private static let nonOverflowPatterns = [
        "rate limit",
        "too many requests",
        "throttl",
    ]

    static func isContextOverflow(_ error: any Error) -> Bool {
        guard case let OpenAICompatibleClientError.httpError(_, message, type, code, body) = error else {
            return false
        }
        let text = [message, type, code, body]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        guard !nonOverflowPatterns.contains(where: text.contains) else { return false }
        return overflowPatterns.contains(where: text.contains)
    }
}
