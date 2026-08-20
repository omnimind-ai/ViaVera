import Foundation

nonisolated struct AgentTimeContextCache: Sendable {
    static let defaultLifetime: TimeInterval = 60 * 60

    private struct Entry: Sendable {
        let value: Date
        let storedAt: Date
    }

    private let lifetime: TimeInterval
    private var entry: Entry?

    init(lifetime: TimeInterval = Self.defaultLifetime) {
        self.lifetime = max(0, lifetime)
    }

    mutating func value(at now: Date = .now) -> Date {
        if let entry {
            let age = now.timeIntervalSince(entry.storedAt)
            if age >= 0, age < lifetime {
                return entry.value
            }
        }

        let value = Self.startOfMinute(containing: now)
        entry = Entry(value: value, storedAt: now)
        return value
    }

    private static func startOfMinute(containing date: Date) -> Date {
        let interval = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: floor(interval / 60) * 60)
    }
}
