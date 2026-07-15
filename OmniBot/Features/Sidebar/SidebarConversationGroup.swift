import Foundation

enum SidebarConversationGroup: Int, CaseIterable, Identifiable {
    case pinned
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    var id: Self { self }

    var title: String {
        switch self {
        case .pinned:
            "置顶"
        case .today:
            "今天"
        case .yesterday:
            "昨天"
        case .thisWeek:
            "这周"
        case .thisMonth:
            "这个月"
        case .older:
            "更久以前"
        }
    }

    static func group(
        for date: Date,
        isPinned: Bool = false,
        relativeTo referenceDate: Date,
        calendar: Calendar
    ) -> Self {
        if isPinned {
            return .pinned
        }

        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return .today
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }

        if let week = calendar.dateInterval(of: .weekOfYear, for: referenceDate),
           week.contains(date) {
            return .thisWeek
        }

        if let month = calendar.dateInterval(of: .month, for: referenceDate),
           month.contains(date) {
            return .thisMonth
        }

        return .older
    }
}
