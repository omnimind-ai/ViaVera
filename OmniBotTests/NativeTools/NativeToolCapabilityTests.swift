import Foundation
import Testing
@testable import Via_Vera

@Suite("Composable native host capabilities")
@MainActor
struct NativeToolCapabilityTests {
    @Test("The TOTP package contains only ordinary components and named capability actions")
    func declarativeTOTP() throws {
        let package = try NativeToolTestFixtures.package("totp")
        func types(_ nodes: [NativeToolComponent]) -> [NativeToolComponent.Kind] { nodes.flatMap { [$0.type] + types($0.children ?? []) } }
        #expect(!package.screens.flatMap { types($0.components) }.contains(.totp))
        #expect(package.initialState.isEmpty)
        let operations = Set(package.actions.values.flatMap { $0 }.compactMap(\.operation))
        #expect(operations.isSuperset(of: ["camera.scanQRCode", "photos.scanQRCode", "files.openText", "otp.previewImport", "otp.commitImport", "otp.snapshot", "clipboard.copy", "otp.encryptBackup"]))
        for operation in operations { _ = try NativeToolCapabilityRegistry.resolve(operation, declared: package.capabilities) }
        #expect(try NativeToolTestFixtures.package("qr-reader").capabilities == ["camera", "clipboard"])
    }

    @Test("Validation rejects undeclared operations, wrong arguments, active refresh and persistent secret bindings")
    func validation() throws {
        let package = try NativeToolTestFixtures.package("qr-reader")
        #expect(throws: NativeToolError.self) { try NativeToolTestFixtures.modifying(package) { $0["capabilities"] = .array([]) } }
        #expect(throws: NativeToolError.self) { try NativeToolTestFixtures.modifying(package) { $0["onRefresh"] = .string("scan") } }
        #expect(throws: NativeToolError.self) {
            try NativeToolTestFixtures.modifying(package) {
                $0["actions"] = .object(["scan": .array([.object(["type": .string("invoke"), "operation": .string("camera.scanQRCode"), "arguments": .object(["secret": .string("forbidden")])])]), "copy": .array([.object(["type": .string("navigate"), "screen": .string("main")])])])
            }
        }
        #expect(throws: NativeToolError.self) {
            try NativeToolTestFixtures.modifying(package) {
                $0["initialState"] = .object(["stored": .string("")])
                $0["actions"] = .object(["scan": .array([.object(["type": .string("set"), "key": .string("stored"), "value": .object(["get": .string("scan")])])]), "copy": .array([.object(["type": .string("navigate"), "screen": .string("main")])])])
            }
        }
    }

    @Test("Agent installation uses the same host camera operation for a non-TOTP tool; results stay out of saved documents")
    func sharedHostAndAgent() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths)
        let bridge = NativeToolAgentBridge(paths: workspace.paths, store: store)
        let package = try NativeToolTestFixtures.package("qr-reader")
        try JSONEncoder().encode(package).write(to: workspace.paths.root.appending(path: "qr.json"))
        let context = AgentToolExecutionContext(runID: UUID(), conversationID: UUID(), workspaceURL: workspace.paths.root)
        let args = try arguments(["path": .string("qr.json")])
        _ = try await bridge.execute("native_tool_validate", arguments: args, context: context)
        let installed = try await bridge.execute("native_tool_install", arguments: args, context: context)
        let id = try #require(installed.metadata["toolID"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let host = NativeToolHostCapabilities(toolID: id, permissions: package.capabilities)
        let runtime = NativeToolRuntime(document: try await store.load(id), store: store, host: host)
        runtime.perform("scan")
        await waitForPresentation(host)
        let request = try #require(host.presentation.request)
        // Replace only the physical scanner result; production dispatch/runtime/storage remain real.
        host.presentation.complete(.success(.text("https://example.com/private-qr")), id: request.id)
        host.presentation.dismissed()
        await runtime.finishActions()
        #expect(runtime.sessionState["scan"]?.objectValue?["text"] == .string("https://example.com/private-qr"))
        #expect(try await store.load(id).state.isEmpty)
        let read = try await bridge.execute("native_tool_read", arguments: arguments(["tool_id": .string(id.uuidString)]), context: context)
        #expect(!read.content.contains("private-qr"))
        runtime.suspend()
        #expect(runtime.sessionState["scan"] == .object([:]))
        let discovery = try await bridge.execute("native_tool_capabilities", arguments: arguments([:]), context: context)
        #expect(discovery.metadata["operations"]?.arrayValue?.count == NativeToolCapabilityRegistry.entries.count)
    }

    @Test("File handles are local to a tool session and arbitrary text uses the common file API")
    func genericFiles() async throws {
        let host = NativeToolHostCapabilities(toolID: UUID(), permissions: ["files"])
        let selection = Task { try await host.invoke("files.openText", arguments: [:]) }
        await waitForPresentation(host)
        let request = try #require(host.presentation.request)
        host.presentation.complete(.success(.data(Data("Generic file content".utf8))), id: request.id)
        host.presentation.dismissed()
        let result = try await selection.value
        let handle = try #require(result.objectValue?["handle"])
        #expect(try await host.invoke("files.readText", arguments: ["handle": handle]).objectValue?["text"] == .string("Generic file content"))
        let another = NativeToolHostCapabilities(toolID: UUID(), permissions: ["files"])
        await #expect(throws: NativeToolError.self) { try await another.invoke("files.readText", arguments: ["handle": handle]) }
        host.suspend()
        await #expect(throws: NativeToolError.self) { try await host.invoke("files.readText", arguments: ["handle": handle]) }
        await #expect(throws: NativeToolError.self) { try await host.invoke("camera.scanQRCode", arguments: [:]) }
        #expect(host.presentation.request == nil)
    }

    @Test("Preview and cancellation cannot invoke or retain host results")
    func previewAndCancellation() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths)
        let record = try await store.install(NativeToolTestFixtures.package("qr-reader"))
        let host = NativeToolHostCapabilities(toolID: record.id, permissions: record.package.capabilities)
        let document = try await store.load(record.id)
        let preview = NativeToolRuntime(document: document, store: store, isPreview: true, host: host)
        preview.perform("scan")
        await preview.finishActions()
        #expect(host.presentation.request == nil && preview.errorMessage != nil)
        let runtime = NativeToolRuntime(document: document, store: store, host: host)
        runtime.perform("scan")
        await waitForPresentation(host)
        runtime.suspend()
        await runtime.finishActions()
        #expect(host.presentation.request == nil)
        #expect(!runtime.isPerforming && runtime.sessionState["scan"] == .object([:]))
    }

    @Test("Existing opaque TOTP packages migrate without changing the vault UUID or user data")
    func migration() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let old = NativeToolPackage(schemaVersion: 1, name: "Original authenticator", summary: nil, symbol: nil, stateVersion: 1,
            initialState: [:], screens: [NativeToolScreen(id: "main", title: "Accounts", components: [NativeToolComponent(id: "otp", type: .totp)])], actions: [:], capabilities: ["totp"])
        let plainStore = NativeToolStore(paths: workspace.paths)
        let record = try await plainStore.install(old)
        let store = NativeToolStore(paths: workspace.paths, builtInTools: [BuiltInNativeTool(id: "totp", package: try NativeToolTestFixtures.package("totp"))])
        let document = try await store.load(record.id)
        #expect(document.record.id == record.id)
        #expect(document.record.package.name == old.name)
        #expect(document.record.package.capabilities.contains("camera"))
        #expect(document.record.revision == 2 && document.state.isEmpty)
        #expect(try await store.load(record.id).record.revision == 2)
    }

    private func waitForPresentation(_ host: NativeToolHostCapabilities) async {
        for _ in 0..<100 { if host.presentation.request != nil { return }; await Task.yield() }
    }

    @Test("Credential revocation clears package passwords and temporary results during passive refresh")
    func revocation() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = NativeToolStore(paths: workspace.paths)
        let record = try await store.install(NativeToolTestFixtures.package("totp"))
        let host = NativeToolHostCapabilities(toolID: record.id, permissions: record.package.capabilities)
        let runtime = NativeToolRuntime(document: try await store.load(record.id), store: store, host: host)
        runtime.setSession(.string("temporary-password"), for: "password")
        runtime.setSession(.object(["text": .string("temporary-secret")]), for: "input")
        host.suspend()
        await runtime.refresh()
        #expect(runtime.sessionState["password"] == .string(""))
        #expect(runtime.sessionState["input"] == .object([:]))
        #expect(runtime.sessionState["otp"]?.objectValue?["unlocked"] == .bool(false))
        #expect(try await store.load(record.id).state.isEmpty)
    }

    @Test("Legacy component expansion preserves unrelated JSON UI and saved state")
    func mixedMigration() throws {
        let package = NativeToolPackage(schemaVersion: 1, name: "Mixed", summary: nil, symbol: nil, stateVersion: 1,
            initialState: ["note": .string("Keep me")], screens: [NativeToolScreen(id: "main", title: "Home", components: [
                NativeToolComponent(id: "note", type: .textField, binding: "note"), NativeToolComponent(id: "otp", type: .totp),
            ])], actions: [:], capabilities: ["totp"])
        let migrated = try #require(NativeToolLegacyMigration.upgrade(package, template: NativeToolTestFixtures.package("totp")))
        try NativeToolValidator.validate(migrated)
        #expect(migrated.initialState == package.initialState)
        #expect(migrated.screens[0].components[0] == package.screens[0].components[0])
        #expect(migrated.screens[0].components[1].type == .button)
        #expect(migrated.screens.count == 5)
        #expect(throws: NativeToolError.self) { try NativeToolValidator.decode(JSONEncoder().encode(package)) }
    }

    private func arguments(_ values: [String: AgentValue]) throws -> OmniToolArguments {
        let values = values.merging(["tool_title": .string("Capability test")]) { old, _ in old }
        return try OmniToolArguments(call: AgentToolCall(id: UUID().uuidString, name: "test", arguments: String(decoding: JSONEncoder().encode(values), as: UTF8.self)))
    }
}
