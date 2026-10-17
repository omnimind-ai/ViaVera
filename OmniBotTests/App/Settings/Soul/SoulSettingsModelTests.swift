import Foundation
import Testing
@testable import Via_Vera

@Suite("SOUL settings")
@MainActor
struct SoulSettingsModelTests {
    @Test("Deleting all content keeps the editor empty")
    func emptySaveDoesNotRestoreDefaultSoul() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = SoulStore(paths: temporary.paths)
        let model = SoulSettingsModel(store: store)
        await model.load()
        model.content = ""

        await model.save("")

        #expect(model.content.isEmpty)
        #expect(try await store.load().isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("An older save never overwrites newer editor content")
    func olderSavePreservesNewerEditorContent() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = SoulStore(paths: temporary.paths)
        let model = SoulSettingsModel(store: store)
        await model.load()
        model.content = "Newer editor content"

        await model.save("Older snapshot")

        #expect(model.content == "Newer editor content")
        #expect(model.persistedContent == "Older snapshot\n")
        #expect(try await store.load() == "Older snapshot\n")
        #expect(model.errorMessage == nil)
    }

    @Test("Both editors load and save their own profiles")
    func profilesLoadAndSaveIndependently() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = SoulStore(paths: temporary.paths)
        try await store.save("Task profile")
        try await store.save("Chat profile", mode: .chat)
        let model = SoulSettingsModel(store: store)

        await model.load()
        #expect(model.content == "Task profile\n")
        #expect(model.chatContent == "Chat profile\n")
        #expect(model.persistedContent == model.content)
        #expect(model.persistedChatContent == model.chatContent)

        model.chatContent = ""
        await model.saveChat("")

        #expect(model.chatContent.isEmpty)
        #expect(model.persistedChatContent == "")
        #expect(try await store.load(mode: .chat).isEmpty)
        #expect(model.content == "Task profile\n")
        #expect(try await store.load() == "Task profile\n")
        #expect(model.errorMessage == nil)
    }

    @Test("An older chat save preserves new edits in both editors")
    func olderChatSavePreservesBothEditors() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = SoulStore(paths: temporary.paths)
        let model = SoulSettingsModel(store: store)
        await model.load()
        model.content = "Unsaved task profile"
        model.chatContent = "Newer chat profile"

        await model.saveChat("Older chat snapshot")

        #expect(model.content == "Unsaved task profile")
        #expect(model.chatContent == "Newer chat profile")
        #expect(model.persistedChatContent == "Older chat snapshot\n")
        #expect(try await store.load(mode: .chat) == "Older chat snapshot\n")
        #expect(try await store.load() == SoulStore.defaultSoul)
        #expect(model.errorMessage == nil)
    }
}
