import Foundation

nonisolated struct ModelUsageSummary: Sendable {
    let range: ModelUsageRange
    let days: [ModelUsageDay]
    let weeks: [ModelUsageWeek]
    let tokenBuckets: [ModelUsageDay]
    let models: [ModelUsageModel]
    let modelsByTokens: [ModelUsageModel]
    let total: ModelUsageDay
    let activeDays: Int
    let longestStreak: Int
    let peakDay: ModelUsageDay?

    var knownModelCount: Int { models.count(where: { $0.modelID != nil }) }
    var hasActivity: Bool { total.messageCount > 0 || total.responseCount > 0 }
    var hasUnknownModels: Bool { models.contains(where: { $0.modelID == nil }) }

    init(
        entries: [ModelUsageEntry],
        range: ModelUsageRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.range = range
        let start = range.startDate(now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var daily: [Date: ModelUsageDay] = [:]
        var modelTotals: [String: ModelUsageModel] = [:]

        for entry in entries where entry.date >= start && entry.date <= now {
            let date = calendar.startOfDay(for: entry.date)
            var day = daily[date] ?? ModelUsageDay(date: date)
            if entry.role == "user" {
                day.messageCount += 1
            } else if entry.isModelResponse {
                var contribution = ModelUsageDay(date: date)
                contribution.responseCount = 1
                contribution.inputTokens = max(0, entry.inputTokens)
                contribution.outputTokens = max(0, entry.outputTokens)
                contribution.cachedTokens = max(0, entry.cachedTokens)
                contribution.cacheCreationTokens = min(
                    contribution.inputTokens, max(0, entry.cacheCreationTokens)
                )
                day.add(contribution)
                let normalized = entry.modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
                var model = ModelUsageModel(modelID: normalized?.isEmpty == false ? normalized : nil)
                model = modelTotals[model.id] ?? model
                model.responseCount += 1
                model.totalTokens = AgentUsage.saturatingSum(model.totalTokens, contribution.totalTokens)
                modelTotals[model.id] = model
            }
            daily[date] = day
        }

        var days: [ModelUsageDay] = []
        var total = ModelUsageDay(date: start)
        var activeDays = 0
        var streak = 0
        var longestStreak = 0
        var buckets: [Date: ModelUsageDay] = [:]
        for offset in 0..<range.rawValue {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = daily[date] ?? ModelUsageDay(date: date)
            days.append(day)
            total.add(day)
            if day.messageCount > 0 {
                activeDays += 1
                streak += 1
                longestStreak = max(longestStreak, streak)
            } else {
                streak = 0
            }
            // Clamp the first partial bucket to the selected interval.
            let bucketDate = max(start, calendar.dateInterval(of: range.bucketComponent, for: date)?.start ?? date)
            var bucket = buckets[bucketDate] ?? ModelUsageDay(date: bucketDate)
            bucket.add(day)
            buckets[bucketDate] = bucket
        }

        self.days = days
        self.total = total
        self.activeDays = activeDays
        self.longestStreak = longestStreak
        self.peakDay = days.filter { $0.messageCount > 0 }.max { $0.messageCount < $1.messageCount }
        self.tokenBuckets = buckets.values.sorted { $0.date < $1.date }
        self.models = modelTotals.values.sorted {
            if $0.responseCount != $1.responseCount { return $0.responseCount > $1.responseCount }
            if $0.totalTokens != $1.totalTokens { return $0.totalTokens > $1.totalTokens }
            return $0.id < $1.id
        }
        self.modelsByTokens = modelTotals.values.sorted {
            if $0.totalTokens != $1.totalTokens { return $0.totalTokens > $1.totalTokens }
            return $0.id < $1.id
        }
        self.weeks = Self.makeWeeks(days: days, start: start, today: today, calendar: calendar)
    }

    private static func makeWeeks(
        days: [ModelUsageDay], start: Date, today: Date, calendar: Calendar
    ) -> [ModelUsageWeek] {
        // Monday-first columns are stable across locale and year boundaries.
        let leadingDays = (calendar.component(.weekday, from: start) + 5) % 7
        guard let firstMonday = calendar.date(byAdding: .day, value: -leadingDays, to: start) else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let columnCount = (leadingDays + days.count + 6) / 7
        var result: [ModelUsageWeek] = []
        var previousMonth: Int?
        for column in 0..<columnCount {
            guard let monday = calendar.date(byAdding: .day, value: column * 7, to: firstMonday) else { continue }
            let cells = (0..<7).map { row -> ModelUsageDay? in
                guard let date = calendar.date(byAdding: .day, value: row, to: monday),
                      date >= start, date <= today else { return nil }
                return lookup[date]
            }
            let firstDate = cells.compactMap { $0?.date }.first ?? monday
            let month = calendar.component(.month, from: firstDate)
            let label = previousMonth != month ? "\(month)月" : nil
            previousMonth = month
            result.append(ModelUsageWeek(date: monday, days: cells, monthLabel: label))
        }
        return result
    }
}
