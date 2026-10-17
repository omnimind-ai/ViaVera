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
    private(set) var persistedLongTermMemory: String?
    var errorMessage: String?

    private let store: MarkdownMemoryStore
    @ObservationIgnored private var longTermMemoryRevision: UInt = 0
    @ObservationIgnored private var draftBaseline: String?
    @ObservationIgnored private var loadRevision: UInt = 0
    @ObservationIgnored private var persistenceRevision: UInt = 0
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(store: MarkdownMemoryStore) {
        self.store = store
    }

    func load() async {
        let revisionAtStart = longTermMemoryRevision
        let persistenceAtStart = persistenceRevision
        let hasUnsavedChanges = persistedLongTermMemory.map { longTermMemory != $0 }
            ?? !longTermMemory.isEmpty
        loadRevision &+= 1
        let currentLoadRevision = loadRevision
        do {
            let persistedLongTermMemory = try await store.loadLongTermMemory()
            let persistedTodayMemory = try await store.loadDailyMemory()
            guard loadRevision == currentLoadRevision,
                  persistenceRevision == persistenceAtStart else { return }
            self.persistedLongTermMemory = persistedLongTermMemory
            if !hasUnsavedChanges, longTermMemoryRevision == revisionAtStart {
                longTermMemory = persistedLongTermMemory
                draftBaseline = persistedLongTermMemory
            } else if longTermMemory == persistedLongTermMemory {
                draftBaseline = persistedLongTermMemory
            }
            todayMemory = persistedTodayMemory
            errorMessage = nil
        } catch {
            guard loadRevision == currentLoadRevision,
                  persistenceRevision == persistenceAtStart else { return }
            errorMessage = error.localizedDescription
        }
    }

    func save(_ contentSnapshot: String) async {
        let previousSave = pendingSave
        let saveTask = Task { [weak self] in
            await previousSave?.value
            guard let self else { return }
            await persist(contentSnapshot)
        }
        pendingSave = saveTask
        await saveTask.value
    }

    private func persist(_ contentSnapshot: String) async {
        persistenceRevision &+= 1
        defer { persistenceRevision &+= 1 }
        do {
            let persistedContent = try await store.saveEditedLongTermMemory(
                contentSnapshot,
                baseline: draftBaseline
            )
            persistedLongTermMemory = persistedContent
            if longTermMemory == contentSnapshot {
                longTermMemory = persistedContent
                draftBaseline = persistedContent
            } else {
                // Newer edits supersede this snapshot, but they have not yet
                // incorporated any background additions merged by the store.
                draftBaseline = contentSnapshot
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
