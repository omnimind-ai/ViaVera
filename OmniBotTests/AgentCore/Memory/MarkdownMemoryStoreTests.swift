import Foundation
import Testing
@testable import Via_Vera

@Suite("Markdown memory")
struct MarkdownMemoryStoreTests {
    @Test("Persists intentionally empty long-term memory")
    func saveEmptyLongTermMemory() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)

        _ = try await store.loadLongTermMemory()
        try await store.saveLongTermMemory("")

        #expect(try await store.loadLongTermMemory().isEmpty)
    }

    @Test("Daily and long-term writes are deduplicated and searchable")
    func deduplicationAndSearch() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-10T08:00:00Z"))
        let store = MarkdownMemoryStore(paths: temporary.paths, timeZone: utc)

        #expect(try await store.appendDailyMemory("Alpine rootfs initialized", at: date))
        #expect(try await !store.appendDailyMemory("  Alpine rootfs initialized  ", at: date))
        #expect(try await store.upsertLongTermMemory("User prefers concise answers"))
        #expect(try await !store.upsertLongTermMemory("User prefers concise answers"))

        let alpineHits = try await store.search("Alpine rootfs", limit: 5)
        #expect(alpineHits.count == 1)
        #expect(alpineHits.first?.text == "Alpine rootfs initialized")

        let context = try await store.promptContext(at: date)
        #expect(context.longTermMemory.contains("concise answers"))
        #expect(context.todayMemory.contains("Alpine rootfs initialized"))
    }

    @Test("Harness failures are redacted, deduplicated, and searchable")
    func harnessFailureJournal() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-10T08:00:00Z"))
        let store = MarkdownMemoryStore(paths: temporary.paths, timeZone: utc)
        let firstRunID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let secondRunID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )

        #expect(try await store.recordHarnessFailure(
            toolName: "terminal_execute",
            summary: "deployment failed token=secret-one",
            runID: firstRunID,
            at: date
        ))
        #expect(try await !store.recordHarnessFailure(
            toolName: "terminal_execute",
            summary: "deployment failed token=secret-two",
            runID: secondRunID,
            at: date
        ))

        let journal = try await store.loadHarnessFailures()
        #expect(journal.contains("[count=2]"))
        #expect(journal.contains("token=[REDACTED]"))
        #expect(!journal.contains("secret-one"))
        #expect(!journal.contains("secret-two"))
        let hits = try await store.search("deployment failed", limit: 5)
        #expect(hits.count == 1)
        #expect(hits.first?.source == .harnessFailure)
    }

    @Test("Long-term and daily writes enforce UTF-8 byte limits")
    func writeByteLimits() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-10T08:00:00Z"))
        let limits = MarkdownMemoryLimits(
            maximumLongTermFileBytes: 40,
            maximumDailyFileBytes: 80,
            maximumDailyFileCount: 4,
            maximumDailyTotalBytes: 200
        )
        let store = MarkdownMemoryStore(
            paths: temporary.paths,
            timeZone: utc,
            limits: limits
        )

        do {
            try await store.saveLongTermMemory(String(repeating: "🧠", count: 10))
            Issue.record("Expected the normalized long-term document to exceed 40 UTF-8 bytes")
        } catch let error as MarkdownMemoryStoreError {
            guard case let .fileTooLarge(file, actualBytes, maximumBytes) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(file == "MEMORY.md")
            #expect(actualBytes == 41)
            #expect(maximumBytes == 40)
        }

        do {
            _ = try await store.appendDailyMemory(
                String(repeating: "é", count: 30),
                at: date
            )
            Issue.record("Expected the timestamped daily document to exceed 80 UTF-8 bytes")
        } catch let error as MarkdownMemoryStoreError {
            guard case let .fileTooLarge(file, actualBytes, maximumBytes) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(file == "2026-07-10.md")
            #expect(actualBytes > 80)
            #expect(maximumBytes == 80)
        }
    }

    @Test("Pre-existing oversized files are rejected before decoding")
    func oversizedExistingFileRead() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let limits = MarkdownMemoryLimits(
            maximumLongTermFileBytes: 64,
            maximumDailyFileBytes: 64,
            maximumDailyFileCount: 4,
            maximumDailyTotalBytes: 256
        )
        let store = MarkdownMemoryStore(paths: temporary.paths, limits: limits)
        _ = try await store.loadLongTermMemory()
        try Data(repeating: 0x61, count: 65).write(
            to: temporary.paths.longTermMemoryFile,
            options: .atomic
        )

        do {
            _ = try await store.loadLongTermMemory()
            Issue.record("Expected the existing oversized file to be rejected")
        } catch let error as MarkdownMemoryStoreError {
            #expect(error == .fileTooLarge(
                file: "MEMORY.md",
                actualBytes: 65,
                maximumBytes: 64
            ))
        }
    }

    @Test("Search rejects a daily inventory with too many files")
    func dailyFileCountLimit() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let limits = MarkdownMemoryLimits(
            maximumLongTermFileBytes: 128,
            maximumDailyFileBytes: 64,
            maximumDailyFileCount: 2,
            maximumDailyTotalBytes: 256
        )
        for day in 1...3 {
            try Data("- item\n".utf8).write(
                to: temporary.paths.shortMemoryDirectory
                    .appending(path: "2026-07-0\(day).md")
            )
        }
        let store = MarkdownMemoryStore(paths: temporary.paths, limits: limits)

        do {
            _ = try await store.search("item")
            Issue.record("Expected the daily file-count quota to reject search")
        } catch let error as MarkdownMemoryStoreError {
            #expect(error == .dailyFileCountExceeded(actual: 3, maximum: 2))
        }
    }

    @Test("Search rejects a daily inventory whose aggregate bytes exceed the quota")
    func dailyTotalByteLimit() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let limits = MarkdownMemoryLimits(
            maximumLongTermFileBytes: 128,
            maximumDailyFileBytes: 10,
            maximumDailyFileCount: 4,
            maximumDailyTotalBytes: 10
        )
        for day in 1...2 {
            try Data(repeating: 0x61, count: 6).write(
                to: temporary.paths.shortMemoryDirectory
                    .appending(path: "2026-07-0\(day).md")
            )
        }
        let store = MarkdownMemoryStore(paths: temporary.paths, limits: limits)

        do {
            _ = try await store.search("item")
            Issue.record("Expected the aggregate daily-byte quota to reject search")
        } catch let error as MarkdownMemoryStoreError {
            #expect(error == .dailyTotalBytesExceeded(
                actualBytes: 12,
                maximumBytes: 10
            ))
        }
    }

    @Test("Daily writes cannot exceed inventory count or aggregate-byte quotas")
    func dailyWriteInventoryLimits() async throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-10T08:00:00Z"))

        let countWorkspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: countWorkspace.root) }
        for day in 1...2 {
            try Data("- item\n".utf8).write(
                to: countWorkspace.paths.shortMemoryDirectory
                    .appending(path: "2026-07-0\(day).md")
            )
        }
        let countStore = MarkdownMemoryStore(
            paths: countWorkspace.paths,
            timeZone: utc,
            limits: MarkdownMemoryLimits(
                maximumLongTermFileBytes: 128,
                maximumDailyFileBytes: 100,
                maximumDailyFileCount: 2,
                maximumDailyTotalBytes: 1_000
            )
        )
        do {
            _ = try await countStore.appendDailyMemory("new item", at: date)
            Issue.record("Expected a new daily file to exceed the count quota")
        } catch let error as MarkdownMemoryStoreError {
            #expect(error == .dailyFileCountExceeded(actual: 3, maximum: 2))
        }

        let totalWorkspace = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: totalWorkspace.root) }
        try Data(repeating: 0x61, count: 30).write(
            to: totalWorkspace.paths.shortMemoryDirectory
                .appending(path: "2026-07-01.md")
        )
        let totalStore = MarkdownMemoryStore(
            paths: totalWorkspace.paths,
            timeZone: utc,
            limits: MarkdownMemoryLimits(
                maximumLongTermFileBytes: 128,
                maximumDailyFileBytes: 100,
                maximumDailyFileCount: 4,
                maximumDailyTotalBytes: 50
            )
        )
        do {
            _ = try await totalStore.appendDailyMemory("x", at: date)
            Issue.record("Expected a new daily file to exceed the aggregate-byte quota")
        } catch let error as MarkdownMemoryStoreError {
            guard case let .dailyTotalBytesExceeded(actualBytes, maximumBytes) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(actualBytes > 50)
            #expect(maximumBytes == 50)
        }
    }

    @Test("Daily memory symbolic links are rejected without reading their targets")
    func dailySymbolicLinkIsRejected() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let target = temporary.root.appending(path: "outside.md")
        try Data("- outside secret\n".utf8).write(to: target)
        let link = temporary.paths.shortMemoryDirectory
            .appending(path: "2026-07-10.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = MarkdownMemoryStore(paths: temporary.paths)

        do {
            _ = try await store.search("outside")
            Issue.record("Expected the daily symlink to be rejected")
        } catch let error as MarkdownMemoryStoreError {
            #expect(error == .symbolicLinkNotAllowed(file: "2026-07-10.md"))
        }
    }
}
