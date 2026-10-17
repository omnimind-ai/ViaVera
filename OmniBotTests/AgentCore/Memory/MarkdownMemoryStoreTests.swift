import Foundation
import Testing
@testable import Via_Vera

@Suite("Markdown memory")
struct MarkdownMemoryStoreTests {
    @Test("Shared memory stays available without a usable task workspace")
    func sharedMemoryWithoutWorkspace() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "OmniBotSharedMemoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: container) }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let paths = WorkspacePaths(
            root: container.appending(path: "workspace"),
            controlRoot: container.appending(path: "control", directoryHint: .isDirectory)
        )
        // A regular file makes this an unusable workspace, not merely a missing one.
        try Data("workspace unavailable".utf8).write(to: paths.root)
        let taskMemory = MarkdownMemoryStore(paths: paths)
        let chatMemory = MarkdownMemoryStore(paths: paths)
        let date = Date()

        try await taskMemory.upsertLongTermMemory("The user prefers concise answers")
        try await chatMemory.appendDailyMemory("The user is planning a train journey", at: date)

        let chatContext = try await chatMemory.sharedPromptMemory(query: "journey", at: date)
        let taskContext = try await taskMemory.sharedPromptMemory(query: "journey", at: date)
        #expect(chatContext == taskContext)
        #expect(taskContext.contains("concise answers"))
        #expect(taskContext.contains("train journey"))
        #expect(try await taskMemory.search("train journey").count == 1)
        #expect(try String(contentsOf: paths.root, encoding: .utf8) == "workspace unavailable")
        #expect(!FileManager.default.fileExists(atPath: paths.agentDirectory.path))
    }

    @Test("Shared prompt keeps related history, deduplicates sources, and excludes tool failures")
    func sharedPromptRetrievalAndDeduplication() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let utc = try #require(TimeZone(identifier: "UTC"))
        let today = try #require(ISO8601DateFormatter().date(from: "2026-07-10T08:00:00Z"))
        let yesterday = today.addingTimeInterval(-86_400)
        let store = MarkdownMemoryStore(paths: temporary.paths, timeZone: utc)
        try await store.saveLongTermMemory("# Preferences\n\nI like travel by train.\n- Use concise answers.")
        try await store.appendDailyMemory("I like travel by train.", at: today)
        try await store.appendDailyMemory("Use concise answers.", at: yesterday)
        try await store.appendDailyMemory("Travel plans include Kyoto.", at: yesterday)
        try await store.recordHarnessFailure(toolName: "terminal_execute", summary: "travel tool failed", runID: UUID())

        let prompt = try await store.sharedPromptMemory(query: "travel", at: today)

        #expect(prompt.components(separatedBy: "I like travel by train.").count == 2)
        #expect(prompt.components(separatedBy: "Use concise answers.").count == 2)
        #expect(prompt.contains("Travel plans include Kyoto."))
        #expect(!prompt.contains("terminal_execute"))
        #expect(!prompt.contains("travel tool failed"))
        // Personal context must not depend on decoding the separate tool journal.
        try Data([0xFF]).write(to: temporary.paths.harnessFailuresFile)
        #expect(try await store.sharedPromptMemory(query: "travel", at: today) == prompt)
    }

    @Test("Shared prompt respects UTF-8 budgets without crowding out recent and relevant memory")
    func sharedPromptByteBudget() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let utc = try #require(TimeZone(identifier: "UTC"))
        let today = try #require(ISO8601DateFormatter().date(from: "2026-07-10T08:00:00Z"))
        let store = MarkdownMemoryStore(paths: temporary.paths, timeZone: utc)
        try await store.upsertLongTermMemory(String(repeating: "家庭👨‍👩‍👧‍👦旅行", count: 200))
        try await store.appendDailyMemory("Today's train booking is confirmed.", at: today)
        try await store.appendDailyMemory("The earlier travel destination was Kyoto.", at: today.addingTimeInterval(-86_400))

        let prompt = try await store.sharedPromptMemory(query: "travel", at: today, maximumUTF8Bytes: 800)
        #expect(prompt.utf8.count <= 800)
        #expect(prompt.contains("家庭👨‍👩‍👧‍👦旅行"))
        #expect(prompt.contains("Today's train booking is confirmed."))
        #expect(prompt.contains("The earlier travel destination was Kyoto."))
        for budget in [0, 1, 2, 30, 59, 127] {
            let bounded = try await store.sharedPromptMemory(query: "travel", at: today, maximumUTF8Bytes: budget)
            #expect(bounded.utf8.count <= budget)
            #expect(String(data: Data(bounded.utf8), encoding: .utf8) == bounded)
            #expect(!bounded.contains("�"))
        }
    }

    @Test("Small shared prompts recall relevant later facts and prefer recent additions on ties")
    func longTermRetrievalRanksBeyondDocumentPrefix() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        let oldEntries = (0..<500).map { "- Unrelated archived detail \($0)." }.joined(separator: "\n")
        try await store.saveLongTermMemory(oldEntries)
        try await store.upsertLongTermMemory("The Silverfin project uses Rust.")
        for index in 0..<10 {
            try await store.upsertLongTermMemory("Recent unrelated detail \(index).")
        }

        let relevant = try await store.sharedPromptMemory(query: "Silverfin", maximumUTF8Bytes: 160)
        #expect(relevant.utf8.count <= 160)
        #expect(relevant.contains("The Silverfin project uses Rust."))
        #expect(!relevant.contains("Unrelated archived detail 0."))

        let recent = try await store.sharedPromptMemory(query: "", maximumUTF8Bytes: 80)
        #expect(recent.utf8.count <= 80)
        #expect(recent.contains("Recent unrelated detail 9."))
    }

    @Test("Editor saves preserve concurrent additions while honoring baseline edits and deletions")
    func editorMergePreservesNewMemories() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        try await store.saveLongTermMemory("# Memory\n- Old preference\n- Remove this detail\n")
        let baseline = try await store.loadLongTermMemory()
        try await store.upsertLongTermMemory("Newly learned travel preference")

        let persisted = try await store.saveEditedLongTermMemory("# Memory\n- Updated preference\n", baseline: baseline)

        #expect(persisted.contains("Updated preference"))
        #expect(persisted.contains("Newly learned travel preference"))
        #expect(!persisted.contains("Old preference"))
        #expect(!persisted.contains("Remove this detail"))
        #expect(try await store.loadLongTermMemory() == persisted)
        let deduplicated = try await store.saveEditedLongTermMemory(persisted, baseline: baseline)
        #expect(deduplicated.components(separatedBy: "Newly learned travel preference").count == 2)
    }

    @Test("Clearing the editor deletes seen memory while retaining newly accumulated notes")
    func emptyEditorMergePreservesOnlyNewMemories() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        try await store.saveLongTermMemory("- Existing memory")
        let baseline = try await store.loadLongTermMemory()
        try await store.upsertLongTermMemory("Background addition")

        #expect(try await store.saveEditedLongTermMemory("", baseline: baseline) == "- Background addition\n")
        #expect(try await store.saveEditedLongTermMemory("", baseline: "- Background addition\n").isEmpty)
    }

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
