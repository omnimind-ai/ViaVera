import Foundation
import Observation

@MainActor
@Observable
final class SoulSettingsModel {
    var content = "" {
        didSet {
            guard content != oldValue else { return }
            contentRevision &+= 1
        }
    }
    var errorMessage: String?

    private let store: SoulStore
    @ObservationIgnored private var contentRevision: UInt = 0

    init(store: SoulStore) {
        self.store = store
    }

    func load() async {
        let revisionAtStart = contentRevision
        do {
            let persistedContent = try await store.load()
            if contentRevision == revisionAtStart {
                content = persistedContent
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        await save(content)
    }

    func save(_ contentSnapshot: String) async {
        do {
            try await store.save(contentSnapshot)
            let persistedContent = try await store.load()
            if content == contentSnapshot {
                content = persistedContent
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
