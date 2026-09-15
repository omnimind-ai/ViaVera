import Foundation
import Testing
@testable import Via_Vera

@Suite("Deletable built-in native tools")
struct BuiltInNativeToolTests {
    private func catalog() throws -> [BuiltInNativeTool] {
        try BuiltInNativeTools.load(from: NativeToolTestFixtures.skillDirectory.deletingLastPathComponent())
    }

    @Test("First load installs the actual TOTP package alongside existing user tools")
    @MainActor
    func firstLoad() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let userTool = try await NativeToolStore(paths: workspace.paths).install(NativeToolTestFixtures.package())
        let store = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        let library = NativeToolLibraryModel(store: store)
        await library.load()
        #expect(library.alert == nil)
        #expect(library.records.count == 2)
        #expect(library.records.contains { $0.id == userTool.id && $0.builtInID == nil })
        let totp = try #require(library.records.first { $0.builtInID == "totp" })
        #expect(try totp.package == NativeToolTestFixtures.package("totp"))
        #expect(!library.hasMissingBuiltInTools)
        #expect(totp.conversationID == nil)
        let runtime = NativeToolRuntime(document: try await store.load(totp.id), store: store)
        #expect(runtime.screen.components.first?.type == .totp)
        await library.load()
        #expect(library.records.count == 2)
        let reopened = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        #expect(try await reopened.list().first { $0.builtInID == "totp" }?.id == totp.id)
    }

    @Test("Deletion survives relaunch; explicit restore creates a fresh tool and retains user tools")
    @MainActor
    func deleteAndRestore() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        let totp = try #require(try await store.list().first)
        let userTool = try await store.install(NativeToolTestFixtures.package())
        // Exercise package deletion only; the UI additionally deletes its Keychain vault.
        try await store.delete(totp.id)
        #expect(try await store.list().map(\.id) == [userTool.id])

        let reopened = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        let library = NativeToolLibraryModel(store: reopened)
        await library.load()
        #expect(library.records.map(\.id) == [userTool.id])
        #expect(library.hasMissingBuiltInTools)
        await library.restoreBuiltInTools()
        #expect(library.alert == nil)
        #expect(library.records.count == 2)
        #expect(!library.hasMissingBuiltInTools)
        let restored = try #require(library.records.first { $0.builtInID == "totp" })
        #expect(restored.id != totp.id)
        #expect(restored.revision == 1)
        #expect(restored.previousPackage == nil)
        #expect(try await reopened.load(restored.id).state.isEmpty)
        await #expect(throws: NativeToolError.self) {
            try await reopened.saveState([:], for: totp.id, packageRevision: 1, expectedStateRevision: 0)
        }
        try await reopened.delete(restored.id)
        #expect(try await NativeToolStore(paths: workspace.paths, builtInTools: catalog()).list().map(\.id) == [userTool.id])
    }

    @Test("Relaunch and restore preserve edits, saved data, favorites and package revisions")
    func preserveEdits() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        let totp = try #require(try await store.list().first)
        let edited = try NativeToolTestFixtures.modifying(totp.package) {
            $0["name"] = .string("My authenticator")
            $0["initialState"] = .object(["note": .string("")])
        }
        _ = try await store.install(edited, updating: totp.id, expectedRevision: 1)
        _ = try await store.saveState(["note": .string("Saved locally")], for: totp.id, packageRevision: 2, expectedStateRevision: 0)
        try await store.setFavorite(true, for: totp.id)
        let before = try await store.load(totp.id)
        let reopened = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        #expect(try await reopened.list().count == 1)
        try await reopened.restoreBuiltInTools()
        let after = try await reopened.load(totp.id)
        #expect(after.record == before.record)
        #expect(after.state == before.state)
        #expect(after.stateRevision == before.stateRevision)
    }

    @Test("An interrupted installation is reconciled without duplicates or overwritten edits")
    func interruptedInstallation() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        let totp = try #require(try await store.list().first)
        try await store.setFavorite(true, for: totp.id)
        let registry = workspace.paths.hostOmniBotDirectory.appending(path: "native-tools/.built-in-tools.json")
        try FileManager.default.removeItem(at: registry)
        let reopened = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        let records = try await reopened.list()
        #expect(records.count == 1)
        #expect(records.first?.id == totp.id)
        #expect(records.first?.isFavorite == true)
        #expect(FileManager.default.fileExists(atPath: registry.path))
    }

    @Test("The Agent can discover the default tool through the same native tool list")
    func agentDiscovery() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths, builtInTools: try catalog())
        let bridge = NativeToolAgentBridge(paths: workspace.paths, store: store)
        let arguments = try OmniToolArguments(call: AgentToolCall(
            id: "list", name: "native_tool_list", arguments: #"{"tool_title":"List tools"}"#
        ))
        let result = try await bridge.execute("native_tool_list", arguments: arguments, context: AgentToolExecutionContext(
            runID: UUID(), conversationID: UUID(), workspaceURL: workspace.paths.root
        ))
        let items = try #require(result.metadata["items"]?.arrayValue)
        #expect(items.count == 1)
        #expect(items.first?.objectValue?["builtIn"] == .bool(true))
        let openURL = try #require(items.first?.objectValue?["openURL"]?.stringValue.flatMap(URL.init(string:)))
        let id = try #require(NativeToolRecord.identifier(from: openURL))
        #expect(try await store.load(id).record.package == NativeToolTestFixtures.package("totp"))
    }
}
