import Foundation
import Testing
@testable import Via_Vera

@Suite("SOUL store")
struct SoulStoreTests {
    @Test("Creates the default SOUL and persists an edit")
    func loadAndSave() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = SoulStore(paths: temporary.paths)

        let initial = try await store.load()
        #expect(initial.contains("小万"))

        try await store.save("# SOUL\n\nKeep answers precise.")
        #expect(try await store.load() == "# SOUL\n\nKeep answers precise.\n")
    }

    @Test("Persists an intentionally empty SOUL")
    func saveEmptySoul() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = SoulStore(paths: temporary.paths)

        _ = try await store.load()
        try await store.save("")

        #expect(try await store.load().isEmpty)
    }
}
