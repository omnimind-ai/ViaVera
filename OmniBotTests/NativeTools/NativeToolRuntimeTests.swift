import Foundation
import Testing
@testable import Via_Vera

@Suite("Native tool packages and runtime")
struct NativeToolRuntimeTests {
    @Test("Bundled recipes validate against the actual runtime", arguments: ["checklist", "calculator", "countdown", "totp"])
    func bundledRecipes(name: String) throws {
        let package = try NativeToolTestFixtures.package(name)
        #expect(!package.screens.isEmpty)
    }

    @Test("Checklist supports add, complete and remove with stable host-assigned identities")
    func checklist() throws {
        let package = try NativeToolTestFixtures.package()
        var state = package.initialState
        state["draft"] = .string("  Buy milk  ")
        state = try NativeToolActionEngine.perform("add", package: package, state: state).state
        let item = try #require(state["tasks"]?.arrayValue?.first)
        #expect(item.objectValue?["title"] == .string("Buy milk"))
        #expect(UUID(uuidString: try #require(item.objectValue?["id"]?.stringValue)) != nil)
        #expect(state["draft"] == .string(""))
        state = try NativeToolActionEngine.perform("toggle", package: package, state: state, item: item).state
        #expect(state["tasks"]?.arrayValue?.first?.objectValue?["done"] == .bool(true))
        state = try NativeToolActionEngine.perform("remove", package: package, state: state, item: item).state
        #expect(state["tasks"] == .array([]))
        let empty = try NativeToolActionEngine.perform("add", package: package, state: state)
        #expect(empty.state["tasks"] == .array([]))
    }

    @Test("Actions fail atomically and conditions avoid invalid branches")
    func atomicActions() throws {
        let original = try NativeToolTestFixtures.package()
        let package = try NativeToolTestFixtures.modifying(original) { object in
            object["actions"] = .object(["fail": .array([
                .object(["type": .string("set"), "key": .string("draft"), "value": .string("changed")]),
                .object(["type": .string("set"), "key": .string("draft"), "value": .object(["op": .string("divide"), "args": .array([.number(1), .number(0)])])]),
            ]), "add": .array([.object(["type": .string("set"), "key": .string("draft"), "value": .string("")])]),
            "toggle": .array([.object(["type": .string("toggleItem"), "key": .string("tasks"), "field": .string("done")])]),
            "remove": .array([.object(["type": .string("remove"), "key": .string("tasks")])])])
        }
        #expect(throws: NativeToolError.self) { try NativeToolActionEngine.perform("fail", package: package, state: original.initialState) }
        #expect(original.initialState["draft"] == .string(""))
        let expression: AgentValue = .object(["op": .string("if"), "args": .array([
            .bool(false), .object(["op": .string("divide"), "args": .array([.number(1), .number(0)])]), .number(42),
        ])])
        #expect(try NativeToolExpression.evaluate(expression, state: [:]) == .number(42))
    }

    @Test("Countdown derives its deadline from the execution clock")
    func countdown() throws {
        let package = try NativeToolTestFixtures.package("countdown")
        let result = try NativeToolActionEngine.perform("start", package: package, state: package.initialState, now: Date(timeIntervalSince1970: 1000))
        #expect(result.state["deadline"] == .number(2500))
    }

    @Test("Rejects unsupported components, capabilities and broken bindings")
    func invalidPackages() throws {
        let package = try NativeToolTestFixtures.package()
        #expect(throws: NativeToolError.self) { try NativeToolTestFixtures.modifying(package) { $0["capabilities"] = .array([.string("shell")]) } }
        #expect(throws: NativeToolError.self) { try NativeToolTestFixtures.modifying(package) { $0["initialState"] = .object(["draft": .number(1), "tasks": .array([])]) } }
        #expect(throws: NativeToolError.self) { try NativeToolTestFixtures.modifying(package) { $0["schemaVersion"] = .number(99) } }
        #expect(throws: NativeToolError.self) { try NativeToolTestFixtures.modifying(package) { $0["script"] = .string("arbitrary code") } }
        let raw = String(decoding: try JSONEncoder().encode(package), as: UTF8.self).replacingOccurrences(of: "textField", with: "webview")
        #expect(throws: NativeToolError.self) { try NativeToolValidator.decode(Data(raw.utf8)) }
    }

    @Test("Deep input and oversized collections are rejected")
    func limits() throws {
        let raw = String(repeating: "[", count: 60) + "0" + String(repeating: "]", count: 60)
        #expect(throws: NativeToolError.self) { try NativeToolValidator.decode(Data(raw.utf8)) }
        let records = (0..<501).map { AgentValue.object(["id": .string(String($0))]) }
        #expect(throws: NativeToolError.self) { try NativeToolValidator.validateState(["records": .array(records)]) }
        let expansion: AgentValue = .object(["op": .string("concat"), "args": .array(Array(repeating: .object(["get": .string("large")]), count: 16))])
        #expect(throws: NativeToolError.self) {
            try NativeToolExpression.evaluate(expansion, state: ["large": .string(String(repeating: "x", count: 32_768))])
        }
        let array = AgentValue.array((0..<40).map { .object(["id": .string(String($0)), "text": .string(String(repeating: "x", count: 10_000))]) })
        let duplicated: AgentValue = .object(["a": .object(["get": .string("large")]), "b": .object(["get": .string("large")]), "c": .object(["get": .string("large")])])
        #expect(throws: NativeToolError.self) { try NativeToolExpression.evaluate(duplicated, state: ["large": array]) }
    }

    @Test("Preview interactions do not create installed tools")
    @MainActor
    func previewIsEphemeral() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths)
        let package = try NativeToolTestFixtures.package()
        let record = NativeToolRecord(id: UUID(), revision: 0, package: package, previousPackage: nil, conversationID: nil, createdAt: .now, updatedAt: .now, isFavorite: false)
        let runtime = NativeToolRuntime(document: NativeToolDocument(record: record, state: package.initialState, stateRevision: 0), store: store, isPreview: true)
        runtime.set(.string("Preview task"), for: "draft")
        runtime.perform("add")
        await runtime.flush()
        #expect(runtime.state["tasks"]?.arrayValue?.count == 1)
        #expect(try await store.list().isEmpty)
    }
}
