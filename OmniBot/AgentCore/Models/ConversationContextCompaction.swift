import Foundation

nonisolated enum ConversationContextCompaction {
    static let summaryPrefix =
        "<context-summary> The following is a summary of the earlier conversation that was compacted to save context space."

    private static let requestPrompt = """
    You are a context compaction engine. Your summary will REPLACE the original messages in the conversation context window — the agent will rely on it to continue working. Write the summary in the same language the user used in the conversation.

    MUST PRESERVE (never omit or shorten):
    - All file paths, directory names, URLs, UUIDs, and identifiers — copy verbatim
    - Commands executed and their outcomes (success/failure/output)
    - Active tasks: what was requested, what's done, what's still pending
    - Key decisions made and their rationale
    - Errors encountered and how they were resolved
    - Important constraints, rules, or user preferences mentioned
    - Any tool calls and their results that affect current state

    STRUCTURE:
    1. Start with a one-line summary of the overall goal
    2. Then a concise narrative of what happened, preserving technical details
    3. End with a "Current state" section: what's done, what's pending, any blockers

    PRIORITIZE recent context over older history — the agent needs to know what it was doing most recently, not just what was discussed early on.

    Do NOT translate or alter code snippets, file paths, identifiers, or error messages. Be concise but never lose information the agent needs to continue.
    """

    static func summaryMessage(_ summary: String) -> AgentMessage {
        let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = normalized.isEmpty
            ? summaryPrefix
            : "\(summaryPrefix)\n\n\(normalized)"
        return .user(content)
    }

    static func requestMessages(
        existingSummary: String?,
        messagesToCompact: [AgentMessage]
    ) -> [AgentMessage] {
        var messages: [AgentMessage] = [.system(requestPrompt)]
        if let existingSummary,
           !existingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(summaryMessage(existingSummary))
        }
        messages.append(contentsOf: messagesToCompact)
        messages.append(.user("Generate the replacement context summary now."))
        return messages
    }
}
