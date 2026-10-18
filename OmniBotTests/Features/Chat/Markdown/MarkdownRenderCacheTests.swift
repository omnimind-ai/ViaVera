import Testing
@testable import Via_Vera

@Suite("Completed Markdown render cache")
struct MarkdownRenderCacheTests {
    @Test("Completed content has blocks immediately and changed text is not stale")
    func completedContentIsAvailableSynchronously() {
        let cache = MarkdownRenderCache()
        let source = "# History\n\nA **completed** response.\n\n```swift\nlet answer = 42\n```"
        let blocks = cache.blocks(for: source)
        #expect(blocks == MarkdownBlockParser.parse(source))
        #expect(blocks.count == 3)
        #expect(cache.cachedBlocks(for: source) == blocks)
        #expect(cache.blocks(for: source + "\n\nMore text") != blocks)
    }

    @Test("The entry budget retains recently accessed replies")
    func leastRecentlyUsedEntryIsEvicted() {
        let cache = MarkdownRenderCache(maximumEntries: 2)
        _ = cache.blocks(for: "first")
        _ = cache.blocks(for: "second")
        _ = cache.blocks(for: "first")
        _ = cache.blocks(for: "third")
        #expect(cache.cachedBlocks(for: "second") == nil)
        #expect(cache.cachedBlocks(for: "first") != nil)
        #expect(cache.cachedBlocks(for: "third") != nil)
    }

    @Test("UTF-8 budget is enforced without oversized replies flushing history")
    func byteBudgetAndOversizedResponses() {
        let cache = MarkdownRenderCache(maximumSourceBytes: 6)
        _ = cache.blocks(for: "你好")
        _ = cache.blocks(for: "世界")
        #expect(cache.cachedBlocks(for: "你好") == nil)
        #expect(cache.cachedBlocks(for: "世界") != nil)
        #expect(!cache.blocks(for: "This response exceeds the cache budget").isEmpty)
        #expect(cache.cachedBlocks(for: "This response exceeds the cache budget") == nil)
        #expect(cache.cachedBlocks(for: "世界") != nil)
    }

    @Test("Background prewarming retains the newest replies within its budget")
    func prewarmingPrioritizesLatestReplies() async {
        let cache = MarkdownRenderCache(maximumEntries: 2, maximumSourceBytes: 20)
        await cache.prewarm(["oldest", "older", "recent", "latest", "latest"])
        #expect(cache.cachedBlocks(for: "oldest") == nil)
        #expect(cache.cachedBlocks(for: "older") == nil)
        #expect(cache.cachedBlocks(for: "recent") != nil)
        #expect(cache.cachedBlocks(for: "latest") != nil)
    }

    @Test("Concurrent prewarming and reads return complete identical blocks")
    func concurrentReads() async {
        let cache = MarkdownRenderCache()
        let source = "# Shared history\n\n- First\n- Second"
        let expected = MarkdownBlockParser.parse(source)
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask { cache.blocks(for: source) == expected }
            }
            for await matches in group { #expect(matches) }
        }
        #expect(cache.cachedBlocks(for: source) == expected)
    }
}
