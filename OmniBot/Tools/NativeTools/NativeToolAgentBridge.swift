import Foundation

nonisolated struct NativeToolAgentBridge {
    let descriptorFileSystem: WorkspaceDescriptorFileSystem
    let nativeToolStore: NativeToolStore

    init(paths: WorkspacePaths, store: NativeToolStore) {
        descriptorFileSystem = WorkspaceDescriptorFileSystem(paths: paths)
        nativeToolStore = store
    }

    func execute(
        _ name: String, arguments: OmniToolArguments, context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        guard ["native_tool_list", "native_tool_read", "native_tool_validate", "native_tool_install", "native_tool_capabilities"].contains(name) else {
            throw NativeToolError("不支持的原生工具操作。")
        }
        if name == "native_tool_capabilities" {
            let catalog = AgentValue.array(NativeToolCapabilityRegistry.entries.map(\.value))
            return AgentToolExecutionResult(content: String(decoding: try JSONEncoder().encode(catalog), as: UTF8.self), metadata: ["operations": catalog])
        }
        if name == "native_tool_list" {
            let records = try await nativeToolStore.list()
            return AgentToolExecutionResult(content: "Found \(records.count) native tool(s).", metadata: [
                "items": .array(records.map(nativeToolMetadata)),
            ])
        }
        if name == "native_tool_read" {
            let id = try nativeToolID(arguments.requiredString("tool_id", maximumLength: 100))
            let record = try await nativeToolStore.load(id).record
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return AgentToolExecutionResult(
                content: String(decoding: try encoder.encode(record.package), as: UTF8.self),
                metadata: nativeToolMetadata(record).objectValue ?? [:]
            )
        }
        let path = try descriptorFileSystem.parse(arguments.requiredString("path", maximumLength: 4096))
        let file = try descriptorFileSystem.readRegularFile(at: path, offset: 0, maximumBytes: NativeToolValidator.maximumPackageBytes + 1)
        guard file.fileSize <= NativeToolValidator.maximumPackageBytes else { throw NativeToolError("工具包不能超过 256 KB。") }
        let package = try NativeToolValidator.decode(file.data)
        if name == "native_tool_validate" {
            return AgentToolExecutionResult(content: "Native tool package is valid: \(package.name)", metadata: [
                "valid": .bool(true), "name": .string(package.name),
                "screens": .number(Double(package.screens.count)),
                "capabilities": .array(package.capabilities.map(AgentValue.string)),
            ])
        }
        let id = try arguments.optionalString("tool_id", maximumLength: 100).map(nativeToolID)
        let expectedRevision = try arguments.integer("expected_revision", range: 1...1_000_000)
        let record = try await nativeToolStore.install(package, updating: id, expectedRevision: expectedRevision, conversationID: context.conversationID)
        return AgentToolExecutionResult(
            content: "已保存原生工具「\(package.name)」。[打开工具](\(record.url.absoluteString))",
            metadata: nativeToolMetadata(record).objectValue ?? [:]
        )
    }

    private func nativeToolID(_ text: String) throws -> UUID {
        guard let id = UUID(uuidString: text) else { throw NativeToolError("工具 ID 必须是 UUID。") }
        return id
    }

    private func nativeToolMetadata(_ record: NativeToolRecord) -> AgentValue {
        .object([
            "toolID": .string(record.id.uuidString), "name": .string(record.package.name),
            "revision": .number(Double(record.revision)), "summary": .string(record.package.summary ?? ""),
            "builtIn": .bool(record.builtInID != nil),
            "openURL": .string(record.url.absoluteString),
        ])
    }
}
