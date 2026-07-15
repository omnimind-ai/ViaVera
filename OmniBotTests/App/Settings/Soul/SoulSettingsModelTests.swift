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
        #expect(try await store.load() == "Older snapshot\n")
        #expect(model.errorMessage == nil)
    }
}
