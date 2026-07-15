import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent memory tools")
struct OmniAgentMemoryToolTests {
    @Test("Daily and long-term memory writes deduplicate, load, and search")
    func completeMemoryFlow() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let utc = try #require(TimeZone(identifier: "UTC"))
        let executor = makeToolExecutor(paths: temporary.paths, timeZone: utc)
        let date = "2026-07-10T08:00:00Z"

        let firstDaily = try await executeTool(
            "memory_write_daily",
            arguments: titledArguments("Remember runtime", [
                "text": .string("Alpine runtime initialized"),
                "date": .string(date),
            ]),
            using: executor,
            paths: temporary.paths
        )
        let duplicateDaily = try await executeTool(
            "memory_write_daily",
            arguments: titledArguments("Remember runtime again", [
                "text": .string("  Alpine runtime initialized  "),
                "date": .string(date),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(firstDaily.metadata["inserted"] == .bool(true))
        #expect(duplicateDaily.metadata["inserted"] == .bool(false))

        let longTerm = try await executeTool(
            "memory_upsert_longterm",
            arguments: titledArguments("Remember preference", [
                "text": .string("User prefers concise answers"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(longTerm.metadata["inserted"] == .bool(true))

        let search = try await executeTool(
            "memory_search",
            arguments: titledArguments("Search runtime memory", [
                "query": .string("Alpine runtime"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(search.content.contains("Alpine runtime initialized"))
        #expect(search.metadata["hitCount"] == .number(1))

        let loaded = try await executeTool(
            "memory_load",
            arguments: titledArguments("Load all memory", [
                "scope": .string("all"),
                "date": .string(date),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(loaded.content.contains("User prefers concise answers"))
        #expect(loaded.content.contains("Alpine runtime initialized"))
    }

    @Test("Store quota errors are returned as tool errors")
    func quotaErrorIsReturned() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(
            paths: temporary.paths,
            memoryLimits: MarkdownMemoryLimits(
                maximumLongTermFileBytes: 32,
                maximumDailyFileBytes: 64,
                maximumDailyFileCount: 4,
                maximumDailyTotalBytes: 256
            )
        )

        let result = try await executeTool(
            "memory_upsert_longterm",
            arguments: titledArguments("Oversized memory", [
                "text": .string(String(repeating: "x", count: 64)),
            ]),
            using: executor,
            paths: temporary.paths
        )

        #expect(result.isError)
        #expect(result.content.contains("the limit is 32 bytes"))
    }
}
