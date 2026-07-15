import Foundation
import Testing
@testable import Via_Vera

@Suite("Sidebar conversation grouping")
struct SidebarConversationGroupTests {
    @Test("Pinned state and dates are assigned to sidebar groups in display order")
    @MainActor
    func assignsDatesToExpectedGroups() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2

        let referenceDate = try date(2026, 7, 15, calendar: calendar)
        let cases: [(Date, SidebarConversationGroup)] = [
            (try date(2026, 7, 15, calendar: calendar), .today),
            (try date(2026, 7, 14, calendar: calendar), .yesterday),
            (try date(2026, 7, 13, calendar: calendar), .thisWeek),
            (try date(2026, 7, 5, calendar: calendar), .thisMonth),
            (try date(2026, 6, 30, calendar: calendar), .older)
        ]

        for (date, expectedGroup) in cases {
            #expect(
                SidebarConversationGroup.group(
                    for: date,
                    relativeTo: referenceDate,
                    calendar: calendar
                ) == expectedGroup
            )
        }

        #expect(
            SidebarConversationGroup.allCases.map(\.title)
                == ["置顶", "今天", "昨天", "这周", "这个月", "更久以前"]
        )
        #expect(
            SidebarConversationGroup.group(
                for: try date(2026, 6, 30, calendar: calendar),
                isPinned: true,
                relativeTo: referenceDate,
                calendar: calendar
            ) == .pinned
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        calendar: Calendar
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: 12
                )
            )
        )
    }
}
