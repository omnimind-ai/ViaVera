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

    var turnUsage: TurnUsagePresentation? {
        (processMessages + visibleMessages).compactMap(\.turnUsage).last
    }

    var elapsedLabel: String {
        guard let first = (processMessages + visibleMessages).first?.message,
              let last = (processMessages + visibleMessages).last?.message else {
            return ""
        }
        let elapsedSeconds = max(
            0,
            Int(last.updatedAt.timeIntervalSince(first.createdAt).rounded())
        )
        guard elapsedSeconds > 0 else { return "" }
        if elapsedSeconds < 60 {
            return "\(elapsedSeconds)s"
        }
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
}
