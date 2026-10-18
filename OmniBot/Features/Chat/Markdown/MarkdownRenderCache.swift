import Foundation
import Synchronization

/// Completed replies must have their real block layout on their first frame.
/// This bounded, thread-safe cache shares parsing with background prewarming.
nonisolated final class MarkdownRenderCache: Sendable {
    static let shared = MarkdownRenderCache()

    private struct Entry: Sendable {
        let blocks: [MarkdownBlock]
        let sourceBytes: Int
        var lastAccess: UInt64
    }

    private struct Storage: Sendable {
        var entries: [String: Entry] = [:]
        var sourceBytes = 0
        var accessCounter: UInt64 = 0
    }

    private let storage = Mutex(Storage())
    private let maximumEntries: Int
    private let maximumSourceBytes: Int

    init(maximumEntries: Int = 256, maximumSourceBytes: Int = 4 * 1_024 * 1_024) {
        self.maximumEntries = max(0, maximumEntries)
        self.maximumSourceBytes = max(0, maximumSourceBytes)
    }

    func cachedBlocks(for source: String) -> [MarkdownBlock]? {
        storage.withLock { state in
            guard var entry = state.entries[source] else { return nil }
            state.accessCounter &+= 1
            entry.lastAccess = state.accessCounter
            state.entries[source] = entry
            return entry.blocks
        }
    }

    func blocks(for source: String) -> [MarkdownBlock] {
        if let cached = cachedBlocks(for: source) { return cached }
        // Never hold the lock while parsing: a cold background entry must not
        // block the main thread from reading a different, already cached reply.
        let blocks = MarkdownBlockParser.parse(source)
        let bytes = source.utf8.count
        guard maximumEntries > 0, bytes <= maximumSourceBytes else { return blocks }
        storage.withLock { state in
            guard state.entries[source] == nil else { return }
            while state.entries.count >= maximumEntries
                || state.sourceBytes > maximumSourceBytes - bytes {
                guard let oldest = state.entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
                state.sourceBytes -= oldest.value.sourceBytes
                state.entries[oldest.key] = nil
            }
            state.accessCounter &+= 1
            state.entries[source] = Entry(blocks: blocks, sourceBytes: bytes, lastAccess: state.accessCounter)
            state.sourceBytes += bytes
        }
        return blocks
    }

    @concurrent
    func prewarm(_ sources: [String]) async {
        // Start with the latest replies, where a newly opened transcript lands.
        // Stop at the budget rather than evicting those replies for older ones.
        var remainingBytes = maximumSourceBytes
        var warmed: Set<String> = []
        for source in sources.reversed() {
            guard !Task.isCancelled, warmed.count < maximumEntries else { return }
            guard !warmed.contains(source) else { continue }
            let bytes = source.utf8.count
            guard bytes <= remainingBytes else { continue }
            _ = blocks(for: source)
            remainingBytes -= bytes
            warmed.insert(source)
        }
    }
}
