import Foundation
import Testing
@testable import Via_Vera

@Suite("Memory settings auto-save")
@MainActor
struct MemorySettingsModelTests {
    @Test("Deleting all long-term memory keeps the editor empty")
    func emptySaveDoesNotRestoreDocumentHeading() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        let model = MemorySettingsModel(store: store)
        await model.load()
        model.longTermMemory = ""

        await model.save("")

        #expect(model.longTermMemory.isEmpty)
        #expect(try await store.loadLongTermMemory().isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("Snapshot saves do not replace newer editor content")
    func snapshotSavePreservesNewerContent() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        let model = MemorySettingsModel(store: store)
        await model.load()

        model.longTermMemory = "newer edit"
        await model.save("older snapshot")

        #expect(model.longTermMemory == "newer edit")
        #expect(model.persistedLongTermMemory?.trimmed == "older snapshot")
        #expect(try await store.loadLongTermMemory().trimmed == "older snapshot")

        await model.save("newer edit")

        #expect(model.longTermMemory.trimmed == "newer edit")
        #expect(try await store.loadLongTermMemory().trimmed == "newer edit")
        #expect(model.errorMessage == nil)
    }

    @Test("Reload shows background memory without making the editor dirty")
    func reloadRefreshesCleanDraftAndBaseline() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        let model = MemorySettingsModel(store: store)
        await model.load()
        try await store.upsertLongTermMemory("Prefers concise replies")

        await model.load()

        #expect(model.longTermMemory.contains("Prefers concise replies"))
        #expect(model.persistedLongTermMemory == model.longTermMemory)
        #expect(model.errorMessage == nil)
    }

    @Test("Dirty reload preserves edits and saving keeps only unseen background additions")
    func dirtyReloadPreservesEditsAndFreshMemory() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        try await store.saveLongTermMemory("- Old preference\n- Remove this fact")
        let model = MemorySettingsModel(store: store)
        await model.load()
        model.longTermMemory = "- Edited preference"
        try await store.upsertLongTermMemory("New background fact")

        await model.load()

        #expect(model.longTermMemory == "- Edited preference")
        #expect(model.persistedLongTermMemory?.contains("New background fact") == true)

        await model.save(model.longTermMemory)

        let persisted = try await store.loadLongTermMemory()
        #expect(persisted == "- Edited preference\n- New background fact\n")
        #expect(model.longTermMemory == persisted)
        #expect(model.persistedLongTermMemory == persisted)
        #expect(model.errorMessage == nil)
    }

    @Test("Older snapshots do not cause obsolete user text to return on the next save")
    func olderSaveRetainsOnlyBackgroundAdditionsForNewerDraft() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = MarkdownMemoryStore(paths: temporary.paths)
        try await store.saveLongTermMemory("- Original")
        let model = MemorySettingsModel(store: store)
        await model.load()
        model.longTermMemory = "- Newer edit"
        try await store.upsertLongTermMemory("Background addition")

        await model.save("- Older edit")
        #expect(model.longTermMemory == "- Newer edit")
        await model.save("- Newer edit")

        let persisted = try await store.loadLongTermMemory()
        #expect(persisted == "- Newer edit\n- Background addition\n")
        #expect(model.persistedLongTermMemory == persisted)
        #expect(model.errorMessage == nil)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
