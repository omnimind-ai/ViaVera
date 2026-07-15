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

        model.longTermMemory = "newer edit"
        await model.save("older snapshot")

        #expect(model.longTermMemory == "newer edit")
        #expect(try await store.loadLongTermMemory().trimmed == "older snapshot")

        await model.save("newer edit")

        #expect(model.longTermMemory.trimmed == "newer edit")
        #expect(try await store.loadLongTermMemory().trimmed == "newer edit")
        #expect(model.errorMessage == nil)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
