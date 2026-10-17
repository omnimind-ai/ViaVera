import Foundation

struct ResponseCompletionPresentation: Equatable {
    let usage: TurnUsagePresentation
    let startedAt: Date
    let completedAt: Date

    var elapsedSeconds: Int {
        max(0, Int(completedAt.timeIntervalSince(startedAt).rounded()))
    }

    var elapsedLabel: String {
        let totalSeconds = elapsedSeconds
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        var components: [String] = []
        if hours > 0 { components.append("\(hours) h") }
        if minutes > 0 { components.append("\(minutes) min") }
        if seconds > 0 || components.isEmpty { components.append("\(seconds) s") }
        return components.joined(separator: " ")
    }
}
