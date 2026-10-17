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

    @Test("Task and chat profiles keep independent values, including an empty chat prompt")
    func profilesRemainIndependent() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let store = SoulStore(paths: temporary.paths)

        try await store.save("Task identity")
        #expect(try await store.load(mode: .chat) == SoulStore.defaultChatSoul)
        try await store.save("Chat identity", mode: .chat)

        #expect(try await store.load() == "Task identity\n")
        #expect(try await store.load(mode: .chat) == "Chat identity\n")
        try await store.save("", mode: .chat)
        #expect(try await store.load(mode: .chat).isEmpty)
        #expect(try await store.load() == "Task identity\n")
    }

    @Test("Chat profile is host-only and does not initialize a workspace")
    func chatProfileNeedsNoWorkspace() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "OmniBotChatSoulTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: container) }
        let paths = WorkspacePaths(
            root: container.appending(path: "workspace", directoryHint: .isDirectory),
            controlRoot: container.appending(path: "control", directoryHint: .isDirectory)
        )
        let store = SoulStore(paths: paths)

        #expect(try await store.load(mode: .chat) == SoulStore.defaultChatSoul)
        try await store.save("Talk naturally", mode: .chat)

        #expect(try await store.load(mode: .chat) == "Talk naturally\n")
        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
        #expect(!FileManager.default.fileExists(atPath: paths.soulFile.path))
        #expect(!FileManager.default.fileExists(atPath: paths.memoryDirectory.path))
        #expect(paths.chatSoulFile.path.hasPrefix(paths.controlRoot.path + "/"))
    }
}
