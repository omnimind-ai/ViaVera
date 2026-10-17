import Foundation

struct AgentTurnPresentation: Identifiable {
    let id: UUID
    let processMessages: [ChatMessagePresentation]
    let visibleMessages: [ChatMessagePresentation]
    let isActive: Bool

    var tools: [ToolCallPresentation] {
        (processMessages + visibleMessages)
            .flatMap(\.toolCalls)
            .filter(\.wasStarted)
    }

    var activityTools: [ToolCallPresentation] {
        tools
    }

    var completion: ResponseCompletionPresentation? {
        guard !isActive else { return nil }
        return (processMessages + visibleMessages).compactMap(\.completion).last
    }
}
