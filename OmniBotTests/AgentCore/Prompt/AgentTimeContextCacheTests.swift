import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent time context cache")
struct AgentTimeContextCacheTests {
    @Test("Keeps coarse date context stable for one hour")
    func reusesCachedMinute() throws {
        let firstRequest = try date("2026-07-10T08:00:47Z")
        let expectedMinute = try date("2026-07-10T08:00:00Z")
        var cache = AgentTimeContextCache()

        let first = cache.value(at: firstRequest)
        let nearExpiry = cache.value(at: firstRequest.addingTimeInterval(3_599.999))

        #expect(first == expectedMinute)
        #expect(nearExpiry == first)
    }

    @Test("Refreshes on the first request after one hour")
    func refreshesAfterLifetime() throws {
        let firstRequest = try date("2026-07-10T08:00:47Z")
        let expectedRefreshedMinute = try date("2026-07-10T09:00:00Z")
        var cache = AgentTimeContextCache()
        let first = cache.value(at: firstRequest)

        let refreshed = cache.value(at: firstRequest.addingTimeInterval(3_600))
        let reused = cache.value(at: firstRequest.addingTimeInterval(7_199))

        #expect(refreshed == expectedRefreshedMinute)
        #expect(refreshed != first)
        #expect(reused == refreshed)
    }

    @Test("Refreshes when the wall clock moves backwards")
    func refreshesAfterClockRollback() throws {
        let firstRequest = try date("2026-07-10T08:00:47Z")
        let expectedRolledBackMinute = try date("2026-07-10T07:58:00Z")
        var cache = AgentTimeContextCache()
        _ = cache.value(at: firstRequest)

        let rolledBack = cache.value(at: try date("2026-07-10T07:58:30Z"))

        #expect(rolledBack == expectedRolledBackMinute)
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
