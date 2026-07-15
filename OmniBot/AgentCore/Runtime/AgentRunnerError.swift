import Foundation

nonisolated public enum AgentRunnerError: Error, LocalizedError, Sendable, Equatable {
    case duplicateRun(UUID)
    case invalidCurrentUserMessage
    case maximumRoundsExceeded(Int)
    case maximumToolCallsPerRoundExceeded(maximum: Int, received: Int)
    case maximumToolCallsPerRunExceeded(Int)
    case modelToolResultBudgetExceeded(Int)
    case assistantToolContextBudgetExceeded(Int)
    case assistantMessageTooLarge(Int)
    case toolCallFieldTooLarge(String, maximumBytes: Int)
    case contextWindowTooSmall(Int)
    case invalidToolCallIdentifiers
    case emptyAssistantResponse
    case outputTruncated
    case contentFiltered

    public var errorDescription: String? {
        switch self {
        case let .duplicateRun(id):
            "An Agent run with ID \(id) is already active."
        case .invalidCurrentUserMessage:
            "The current message must have the user role."
        case let .maximumRoundsExceeded(maximum):
            "The Agent exceeded the maximum of \(maximum) rounds."
        case let .maximumToolCallsPerRoundExceeded(maximum, received):
            "The model returned \(received) tool calls in one round, exceeding the maximum of \(maximum)."
        case let .maximumToolCallsPerRunExceeded(maximum):
            "The Agent exceeded the maximum of \(maximum) tool calls in one run."
        case let .modelToolResultBudgetExceeded(maximumBytes):
            "The Agent exhausted its \(maximumBytes)-byte tool-result context budget."
        case let .assistantToolContextBudgetExceeded(maximumBytes):
            "The model exceeded the \(maximumBytes)-byte intermediate response budget."
        case let .assistantMessageTooLarge(maximumBytes):
            "The model response exceeded the \(maximumBytes)-byte Agent message limit."
        case let .toolCallFieldTooLarge(field, maximumBytes):
            "The model returned a tool-call \(field) larger than \(maximumBytes) bytes."
        case let .contextWindowTooSmall(contextWindow):
            "The configured \(contextWindow)-token context window is too small for the Agent prompt and reserved tool context."
        case .invalidToolCallIdentifiers:
            "The model returned empty or duplicate tool-call identifiers."
        case .emptyAssistantResponse:
            "The model returned neither content nor tool calls."
        case .outputTruncated:
            "The model stopped because it reached the output token limit."
        case .contentFiltered:
            "The model response was blocked by the provider's content filter."
        }
    }
}
