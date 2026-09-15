import Foundation

/// Host-owned tool packages and data. Only source packages cross the Agent boundary.
actor NativeToolStore {
    nonisolated static let didChange = Notification.Name("OmniBot.NativeTools.didChange")
    nonisolated let builtInTools: [BuiltInNativeTool]
    private let directory: URL
    private let fileManager = FileManager.default

    init(paths: WorkspacePaths, builtInTools: [BuiltInNativeTool] = []) {
        directory = paths.hostOmniBotDirectory.appending(path: "native-tools", directoryHint: .isDirectory)
        self.builtInTools = builtInTools
    }

    func list() throws -> [NativeToolRecord] {
        try prepare()
        try installBuiltInTools(restoreDeleted: false)
        return try storedRecords()
    }

    /// Only restores missing tools. Existing edits and data are preserved.
    func restoreBuiltInTools() throws {
        try prepare()
        try installBuiltInTools(restoreDeleted: true)
    }

    private func storedRecords() throws -> [NativeToolRecord] {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let records = try files.filter { $0.pathExtension == "json" }.map { url in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                throw NativeToolError("工具目录中存在无法识别的记录。")
            }
            return try load(id).record
        }
        return records.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func load(_ id: UUID) throws -> NativeToolDocument {
        let url = fileURL(id)
        guard fileManager.fileExists(atPath: url.path) else { throw NativeToolError("工具不存在或已经删除。") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 2 * 1_024 * 1_024 else { throw NativeToolError("工具记录无效或过大。") }
        var document = try JSONDecoder().decode(NativeToolDocument.self, from: Data(contentsOf: url))
        guard document.record.id == id else { throw NativeToolError("工具记录身份不匹配。") }
        var migrated = false
        if let template = builtInTools.first(where: { $0.id == "totp" })?.package,
           let package = NativeToolLegacyMigration.upgrade(document.record.package, template: template) {
            document.record.package = package
            if let previous = document.record.previousPackage {
                document.record.previousPackage = NativeToolLegacyMigration.upgrade(previous, template: template) ?? previous
            }
            document.record.revision += 1
            migrated = true
        }
        try NativeToolValidator.validate(document.record.package)
        try NativeToolValidator.validateState(document.state)
        try NativeToolActionEngine.validateTypes(document.state, package: document.record.package)
        if migrated { try write(document) }
        return document
    }

    @discardableResult
    func install(
        _ package: NativeToolPackage, updating id: UUID? = nil,
        expectedRevision: Int? = nil, conversationID: UUID? = nil
    ) throws -> NativeToolRecord {
        try NativeToolValidator.validate(package)
        try prepare()
        var document: NativeToolDocument
        if let id {
            document = try load(id)
            guard document.record.revision == expectedRevision else {
                throw NativeToolError("工具已更新。请先读取最新工具包，再提交修改。")
            }
            let merged = package.initialState.merging(document.state) { _, saved in saved }
            try NativeToolActionEngine.validateTypes(merged, package: package)
            try NativeToolValidator.validateState(merged)
            document.state = merged
            document.record.previousPackage = document.record.package
            document.record.package = package
            document.record.revision += 1
            document.record.updatedAt = .now
            if let conversationID { document.record.conversationID = conversationID }
        } else {
            guard try list().count < 200 else { throw NativeToolError("最多安装 200 个工具。") }
            let record = NativeToolRecord(
                id: UUID(), revision: 1, package: package, previousPackage: nil,
                conversationID: conversationID, createdAt: .now, updatedAt: .now, isFavorite: false
            )
            document = NativeToolDocument(record: record, state: package.initialState, stateRevision: 0)
        }
        try write(document)
        changed()
        return document.record
    }

    func saveState(
        _ state: [String: AgentValue], for id: UUID,
        packageRevision: Int, expectedStateRevision: Int
    ) throws -> Int {
        var document = try load(id)
        guard document.record.revision == packageRevision,
              document.stateRevision == expectedStateRevision else {
            throw NativeToolError("工具或数据已在其他页面更新，请重新载入后继续。")
        }
        try NativeToolActionEngine.validateTypes(state, package: document.record.package)
        try NativeToolValidator.validateState(state)
        document.state = state
        document.stateRevision += 1
        try write(document)
        return document.stateRevision
    }

    func setFavorite(_ favorite: Bool, for id: UUID) throws {
        var document = try load(id)
        document.record.isFavorite = favorite
        try write(document)
        changed()
    }

    func rollback(_ id: UUID, expectedRevision: Int) throws {
        var document = try load(id)
        guard document.record.revision == expectedRevision, let previous = document.record.previousPackage else {
            throw NativeToolError("没有可恢复的上一版本，或工具已经更新。")
        }
        try NativeToolActionEngine.validateTypes(document.state, package: previous)
        document.record.previousPackage = document.record.package
        document.record.package = previous
        document.record.revision += 1
        document.record.updatedAt = .now
        try write(document)
        changed()
    }

    func delete(_ id: UUID) throws {
        let document = try load(id)
        if let builtInID = document.record.builtInID {
            var installed = try installedBuiltInIDs()
            if installed.insert(builtInID).inserted { try writeInstalledBuiltInIDs(installed) }
        }
        try fileManager.removeItem(at: fileURL(id))
        changed()
    }

    private var builtInRegistryURL: URL { directory.appending(path: ".built-in-tools.json") }

    private func installBuiltInTools(restoreDeleted: Bool) throws {
        guard !builtInTools.isEmpty else { return }
        var installed = try installedBuiltInIDs()
        let pending = builtInTools.filter { restoreDeleted || !installed.contains($0.id) }
        guard !pending.isEmpty else { return }
        var records = try storedRecords()
        for tool in pending {
            if !records.contains(where: { $0.builtInID == tool.id }) {
                guard records.count < 200 else {
                    if restoreDeleted { throw NativeToolError("最多安装 200 个工具。") }
                    continue
                }
                try NativeToolValidator.validate(tool.package)
                let record = NativeToolRecord(
                    id: UUID(), revision: 1, package: tool.package, previousPackage: nil,
                    conversationID: nil, createdAt: .now, updatedAt: .now, isFavorite: false,
                    builtInID: tool.id
                )
                try write(NativeToolDocument(record: record, state: tool.package.initialState, stateRevision: 0))
                records.append(record)
                changed()
            }
            // Write after the tool. An interrupted install is reconciled by builtInID.
            if installed.insert(tool.id).inserted { try writeInstalledBuiltInIDs(installed) }
        }
    }

    private func installedBuiltInIDs() throws -> Set<String> {
        guard fileManager.fileExists(atPath: builtInRegistryURL.path) else { return [] }
        let values = try builtInRegistryURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 64 * 1_024 else { throw NativeToolError("内置工具安装记录无效。") }
        return try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: builtInRegistryURL))
    }

    private func writeInstalledBuiltInIDs(_ installed: Set<String>) throws {
        try JSONEncoder().encode(installed.sorted()).write(to: builtInRegistryURL, options: .atomic)
    }

    private func fileURL(_ id: UUID) -> URL { directory.appending(path: id.uuidString + ".json") }

    private func prepare() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw NativeToolError("工具存储目录不可用。") }
    }

    private func write(_ document: NativeToolDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 2 * 1_024 * 1_024 else { throw NativeToolError("工具记录超过存储上限。") }
        try data.write(to: fileURL(document.record.id), options: .atomic)
    }

    private func changed() { NotificationCenter.default.post(name: Self.didChange, object: nil) }
}
