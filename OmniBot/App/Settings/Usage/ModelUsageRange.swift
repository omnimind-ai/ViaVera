import Foundation

nonisolated enum ModelUsageRange: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365

    var id: Self { self }
    var title: String { "近 \(rawValue) 天" }

    var bucketComponent: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year: .month
        }
    }

    var bucketTitle: String {
        switch self {
        case .week, .month: "每日"
        case .quarter: "每周"
        case .year: "每月"
        }
    }

    func startDate(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1 - rawValue, to: today) ?? today
    }
}
