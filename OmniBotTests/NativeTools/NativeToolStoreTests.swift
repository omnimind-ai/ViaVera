import Foundation
import Testing
@testable import Via_Vera

@Suite("Native tool persistence and Agent boundary")
struct NativeToolStoreTests {
    @Test("Update and rollback preserve data, reject stale writers, and isolate copies")
    func lifecycle() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths)
        let package = try NativeToolTestFixtures.package()
        let first = try await store.install(package)
        let second = try await store.install(package)
        var state = package.initialState
        state["draft"] = .string("PRIVATE USER DATA")
        let stateRevision = try await store.saveState(state, for: first.id, packageRevision: 1, expectedStateRevision: 0)
        #expect(stateRevision == 1)
        #expect(try await store.load(second.id).state["draft"] == .string(""))

        let updatedPackage = try NativeToolTestFixtures.modifying(package) { $0["name"] = .string("Updated checklist") }
        let updated = try await store.install(updatedPackage, updating: first.id, expectedRevision: 1)
        #expect(updated.revision == 2)
        #expect(try await store.load(first.id).state["draft"] == .string("PRIVATE USER DATA"))
        await #expect(throws: NativeToolError.self) { try await store.install(package, updating: first.id, expectedRevision: 1) }
        await #expect(throws: NativeToolError.self) { try await store.saveState(state, for: first.id, packageRevision: 1, expectedStateRevision: 1) }

        try await store.rollback(first.id, expectedRevision: 2)
        let reopened = try await NativeToolStore(paths: workspace.paths).load(first.id)
        #expect(reopened.record.package.name == package.name)
        #expect(reopened.record.revision == 3)
        #expect(reopened.state["draft"] == .string("PRIVATE USER DATA"))
        try await store.delete(first.id)
        #expect(try await store.list().map(\.id) == [second.id])
    }

    @Test("Agent validates, installs and reads source without exposing live data")
    func agentBridge() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths)
        let bridge = NativeToolAgentBridge(paths: workspace.paths, store: store)
        let package = try NativeToolTestFixtures.package()
        try JSONEncoder().encode(package).write(to: workspace.paths.root.appending(path: "tool.json"))
        let context = AgentToolExecutionContext(runID: UUID(), conversationID: UUID(), workspaceURL: workspace.paths.root)
        let validated = try await bridge.execute("native_tool_validate", arguments: arguments(["path": .string("tool.json")]), context: context)
        #expect(validated.metadata["valid"] == .bool(true))
        let installed = try await bridge.execute("native_tool_install", arguments: arguments(["path": .string("tool.json")]), context: context)
        let idString = try #require(installed.metadata["toolID"]?.stringValue)
        let id = try #require(UUID(uuidString: idString))
        let urlString = try #require(installed.metadata["openURL"]?.stringValue)
        let url = try #require(URL(string: urlString))
        #expect(NativeToolRecord.identifier(from: url) == id)
        var state = package.initialState
        state["draft"] = .string("PRIVATE USER DATA")
        _ = try await store.saveState(state, for: id, packageRevision: 1, expectedStateRevision: 0)
        let read = try await bridge.execute("native_tool_read", arguments: arguments(["tool_id": .string(id.uuidString)]), context: context)
        #expect(!read.content.contains("PRIVATE USER DATA"))
        #expect(!read.content.contains(workspace.root.path))
        #expect(read.metadata["revision"] == .number(1))
        #expect(try NativeToolValidator.decode(Data(read.content.utf8)) == package)

        try FileManager.default.createSymbolicLink(at: workspace.paths.root.appending(path: "escape.json"), withDestinationURL: workspace.paths.controlRoot.appending(path: "secret.json"))
        try Data("private".utf8).write(to: workspace.paths.controlRoot.appending(path: "secret.json"))
        await #expect(throws: (any Error).self) {
            try await bridge.execute("native_tool_install", arguments: arguments(["path": .string("escape.json")]), context: context)
        }
    }

    @Test("Persisted edits are serialized and stale state changes cannot overwrite newer ones")
    @MainActor
    func serializedRuntimeWrites() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths)
        let record = try await store.install(NativeToolTestFixtures.package())
        let document = try await store.load(record.id)
        let runtime = NativeToolRuntime(document: document, store: store)
        runtime.set(.string("a"), for: "draft")
        runtime.set(.string("ab"), for: "draft")
        runtime.set(.string("abc"), for: "draft")
        await runtime.flush()
        #expect(try await store.load(record.id).state["draft"] == .string("abc"))
        let stale = NativeToolRuntime(document: document, store: store)
        stale.set(.string("old"), for: "draft")
        await stale.flush()
        #expect(stale.persistenceFailed)
        #expect(try await store.load(record.id).state["draft"] == .string("abc"))
    }

    private func arguments(_ values: [String: AgentValue]) throws -> OmniToolArguments {
        var values = values
        values["tool_title"] = .string("Native tool test")
        let data = try JSONEncoder().encode(AgentValue.object(values))
        return try OmniToolArguments(call: AgentToolCall(id: UUID().uuidString, name: "test", arguments: String(decoding: data, as: UTF8.self)))
    }
}
