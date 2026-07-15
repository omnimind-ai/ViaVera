import Foundation
import Observation

@MainActor
@Observable
final class MemorySettingsModel {
    var longTermMemory = "" {
        didSet {
            guard longTermMemory != oldValue else { return }
            longTermMemoryRevision &+= 1
        }
    }
    private(set) var todayMemory = ""
    var errorMessage: String?

    private let store: MarkdownMemoryStore
    @ObservationIgnored private var longTermMemoryRevision: UInt = 0

    init(store: MarkdownMemoryStore) {
        self.store = store
    }

    func load() async {
        let revisionAtStart = longTermMemoryRevision
        do {
            let persistedLongTermMemory = try await store.loadLongTermMemory()
            let persistedTodayMemory = try await store.loadDailyMemory()
            if longTermMemoryRevision == revisionAtStart {
                longTermMemory = persistedLongTermMemory
            }
            todayMemory = persistedTodayMemory
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ contentSnapshot: String) async {
        do {
            try await store.saveLongTermMemory(contentSnapshot)
            let persistedContent = try await store.loadLongTermMemory()
            if longTermMemory == contentSnapshot {
                longTermMemory = persistedContent
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
