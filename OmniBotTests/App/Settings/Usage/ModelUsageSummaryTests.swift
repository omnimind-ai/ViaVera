import Foundation
import Testing
@testable import Via_Vera

@Suite("Model usage aggregation")
struct ModelUsageSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    @Test("Counts sent messages and model responses without counting tools or cache writes twice")
    func accounting() throws {
        let now = try date(2026, 9, 7)
        let entries: [ModelUsageEntry] = [
            .init(date: now, role: "user", status: "completed", modelID: "a"),
            .init(date: now, role: "assistant", status: "completed", modelID: "a",
                  inputTokens: 100, outputTokens: 30, cachedTokens: 70, cacheCreationTokens: 40),
            .init(date: now, role: "tool", status: "completed", modelID: "a", inputTokens: 999),
            .init(date: now, role: "system", status: "completed", modelID: "a"),
            .init(date: now, role: "assistant", status: "streaming", modelID: "b"),
            .init(date: now, role: "assistant", status: "interrupted", modelID: "b", outputTokens: 10),
        ]
        let summary = ModelUsageSummary(entries: entries, range: .week, now: now, calendar: calendar)

        #expect(summary.total.messageCount == 1)
        #expect(summary.total.responseCount == 2)
        #expect(summary.total.inputTokens == 100)
        #expect(summary.total.cachedTokens == 70)
        #expect(summary.total.cacheCreationTokens == 40)
        #expect(summary.total.outputTokens == 40)
        #expect(summary.total.totalTokens == 210)
        #expect(summary.models.first?.modelID == "a")
        #expect(summary.models.first?.totalTokens == 200)
        #expect(summary.tokenBuckets.reduce(0) { $0 + $1.totalTokens } == 210)
    }

    @Test("Missing model attribution stays separate and missing telemetry remains zero")
    func missingAttribution() throws {
        let now = try date(2026, 9, 7)
        let entries: [ModelUsageEntry] = [
            .init(date: now, role: "assistant", status: "completed", modelID: nil),
            .init(date: now, role: "assistant", status: "completed", modelID: "  "),
            .init(date: now, role: "assistant", status: "completed", modelID: "new-model", outputTokens: 90),
        ]
        let summary = ModelUsageSummary(entries: entries, range: .month, now: now, calendar: calendar)

        #expect(summary.models.count == 2)
        #expect(summary.knownModelCount == 1)
        #expect(summary.hasUnknownModels)
        #expect(summary.models.first?.modelID == nil)
        #expect(summary.models.first?.responseCount == 2)
        #expect(summary.models.first?.totalTokens == 0)
        #expect(summary.modelsByTokens.first?.modelID == "new-model")
    }

    @Test("Uses inclusive local days, excludes future records and keeps zero days in the calendar")
    func boundaries() throws {
        let now = try date(2026, 1, 3)
        let start = ModelUsageRange.week.startDate(now: now, calendar: calendar)
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let entries: [ModelUsageEntry] = [
            .init(date: start.addingTimeInterval(-1), role: "user", status: "completed", modelID: nil),
            .init(date: start, role: "user", status: "completed", modelID: nil),
            .init(date: nextDay, role: "user", status: "completed", modelID: nil),
            .init(date: now, role: "user", status: "completed", modelID: nil),
            .init(date: now.addingTimeInterval(1), role: "user", status: "completed", modelID: nil),
        ]
        let summary = ModelUsageSummary(entries: entries, range: .week, now: now, calendar: calendar)

        #expect(summary.days.count == 7)
        #expect(summary.total.messageCount == 3)
        #expect(summary.activeDays == 3)
        #expect(summary.longestStreak == 2)
        #expect(summary.weeks.flatMap(\.days).compactMap { $0 }.count == 7)
        #expect(summary.weeks.allSatisfy { $0.days.count == 7 })
        #expect(summary.weeks.allSatisfy { calendar.component(.weekday, from: $0.date) == 2 })
        #expect(summary.days.count(where: { $0.messageCount == 0 }) == 4)
    }

    @Test("Day iteration respects daylight saving time")
    func daylightSaving() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(local.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
        let summary = ModelUsageSummary(entries: [], range: .week, now: now, calendar: local)

        #expect(summary.days.count == 7)
        #expect(Set(summary.days.map(\.date)).count == 7)
        #expect(summary.days.allSatisfy { local.component(.hour, from: $0.date) == 0 })
        let march8 = try #require(summary.days.first { local.component(.day, from: $0.date) == 8 })
        let march9 = try #require(summary.days.first { local.component(.day, from: $0.date) == 9 })
        #expect(march9.date.timeIntervalSince(march8.date) == 23 * 60 * 60)
    }

    @Test("Weekly and monthly buckets preserve totals through leap years and partial periods",
          arguments: [ModelUsageRange.quarter, .year])
    func bucketTotals(range: ModelUsageRange) throws {
        let now = try date(2024, 3, 2)
        let start = range.startDate(now: now, calendar: calendar)
        let entries = (0..<range.rawValue).compactMap { offset -> ModelUsageEntry? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return .init(date: day, role: "assistant", status: "completed", modelID: "model", inputTokens: 1)
        }
        let summary = ModelUsageSummary(entries: entries, range: range, now: now, calendar: calendar)

        #expect(summary.days.count == range.rawValue)
        #expect(summary.total.totalTokens == range.rawValue)
        #expect(summary.tokenBuckets.reduce(0) { $0 + $1.totalTokens } == range.rawValue)
        #expect(summary.tokenBuckets.first?.date == start)
        #expect(summary.tokenBuckets.count <= 15)
        #expect(summary.days.contains {
            calendar.component(.month, from: $0.date) == 2 && calendar.component(.day, from: $0.date) == 29
        })
    }

    @Test("Malformed negative usage does not create negative bars and totals saturate safely")
    func invalidCounters() throws {
        let now = try date(2026, 9, 7)
        let summary = ModelUsageSummary(entries: [
            .init(date: now, role: "assistant", status: "completed", modelID: "model",
                  inputTokens: -20, outputTokens: 5, cachedTokens: -2, cacheCreationTokens: 9),
            .init(date: now, role: "assistant", status: "completed", modelID: "model",
                  inputTokens: Int.max, outputTokens: 1),
        ], range: .week, now: now, calendar: calendar)

        #expect(summary.total.cachedTokens == 0)
        #expect(summary.total.cacheCreationTokens == 0)
        #expect(summary.total.totalTokens == Int.max)
        #expect(summary.models.first?.totalTokens == Int.max)
    }

    @Test("Empty histories produce a complete zero-filled calendar")
    func emptyHistory() throws {
        let summary = ModelUsageSummary(entries: [], range: .year, now: try date(2026, 9, 7), calendar: calendar)
        #expect(!summary.hasActivity)
        #expect(summary.total.totalTokens == 0)
        #expect(summary.days.count == 365)
        #expect(summary.models.isEmpty)
        #expect(summary.peakDay == nil)
        #expect(summary.activeDays == 0)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
}
