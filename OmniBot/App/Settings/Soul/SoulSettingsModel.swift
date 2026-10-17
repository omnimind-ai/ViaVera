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
    var chatContent = "" {
        didSet {
            guard chatContent != oldValue else { return }
            chatContentRevision &+= 1
        }
    }
    var errorMessage: String? { taskErrorMessage ?? chatErrorMessage }
    private(set) var persistedContent: String?
    private(set) var persistedChatContent: String?

    private let store: SoulStore
    private var taskErrorMessage: String?
    private var chatErrorMessage: String?
    @ObservationIgnored private var contentRevision: UInt = 0
    @ObservationIgnored private var chatContentRevision: UInt = 0

    init(store: SoulStore) {
        self.store = store
    }

    func load() async {
        // Capture both revisions before either await so an edit to the other
        // profile while the first profile loads is also preserved.
        let revisionAtStart = contentRevision
        let chatRevisionAtStart = chatContentRevision
        do {
            let persistedContent = try await store.load()
            self.persistedContent = persistedContent
            if contentRevision == revisionAtStart {
                content = persistedContent
            }
            taskErrorMessage = nil
        } catch {
            taskErrorMessage = error.localizedDescription
        }
        do {
            let persistedContent = try await store.load(mode: .chat)
            persistedChatContent = persistedContent
            if chatContentRevision == chatRevisionAtStart {
                chatContent = persistedContent
            }
            chatErrorMessage = nil
        } catch {
            chatErrorMessage = error.localizedDescription
        }
    }

    func save() async {
        await save(content)
    }

    func save(_ contentSnapshot: String) async {
        do {
            try await store.save(contentSnapshot)
            let persistedContent = try await store.load()
            self.persistedContent = persistedContent
            if content == contentSnapshot {
                content = persistedContent
            }
            taskErrorMessage = nil
        } catch {
            taskErrorMessage = error.localizedDescription
        }
    }

    func saveChat(_ contentSnapshot: String) async {
        do {
            try await store.save(contentSnapshot, mode: .chat)
            let persistedContent = try await store.load(mode: .chat)
            persistedChatContent = persistedContent
            if chatContent == contentSnapshot {
                chatContent = persistedContent
            }
            chatErrorMessage = nil
        } catch {
            chatErrorMessage = error.localizedDescription
        }
    }
}
