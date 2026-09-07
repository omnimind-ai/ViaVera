import Foundation

nonisolated struct ModelUsageWeek: Identifiable, Sendable {
    let date: Date
    let days: [ModelUsageDay?]
    let monthLabel: String?

    var id: Date { date }
}
