import Foundation

public actor AgentSkillStore {
    private struct ParsedDocument {
        let frontmatter: [String: String]
        let body: String
    }

    private struct IndexedSkill {
        let entry: AgentSkillIndexEntry
        let authoritativeRoot: URL
        let authoritativeSkillFile: URL
    }

    private struct ImportSelection {
        let sourceRoot: URL
        let skillFile: URL
        let copiesEntireDirectory: Bool
    }

    private struct SkillRegistry: Codable {
        let version: Int
        var enabledSkillIDs: [String]

        init(version: Int = 1, enabledSkillIDs: [String] = []) {
            self.version = version
            self.enabledSkillIDs = enabledSkillIDs
        }
    }

    private let paths: WorkspacePaths
    private let resourceProtocol: AgentResourceProtocol
    private let fileManager: FileManager
    private let workspaceFileSystem: WorkspaceDescriptorFileSystem
    private let importLimits: AgentSkillImportLimits
    private let maximumInstalledSkills = 256
    private let maximumRegistryBytes = 64 * 1_024
    private let maximumProjectionFiles = 4_096
    private let maximumProjectionBytes: Int64 = 64 * 1_024 * 1_024

    public init(
        paths: WorkspacePaths,
        importLimits: AgentSkillImportLimits = .default
    ) {
        self.paths = paths
        resourceProtocol = AgentResourceProtocol(paths: paths)
        fileManager = .default
        workspaceFileSystem = WorkspaceDescriptorFileSystem(paths: paths)
        self.importLimits = importLimits
    }

    /// Lists host-authoritative skills. Disabled skills may be shown for
    /// management, but PromptBuilder filters them from model context.
    public func list(query: String = "", limit: Int = 200) throws -> [AgentSkillIndexEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try scan()
            .map(\.entry)
            .filter { entry in
                guard !normalizedQuery.isEmpty else { return true }
                return [
                    entry.id,
                    entry.name,
                    entry.description,
                    entry.rootPath,
                    entry.skillFilePath,
                ].contains { $0.localizedStandardContains(normalizedQuery) }
            }
            .prefix(max(1, min(limit, 200)))
            .map { $0 }
    }

    public func read(
        _ identifier: String,
        maximumCharacters: Int = 64_000,
        triggerReason: String = "Agent requested the installed skill"
    ) throws -> ResolvedAgentSkill {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw AgentSkillStoreError.missingIdentifier }
        let record = try matchingRecord(identifier: normalized, in: scan())
        guard record.entry.enabled else { throw AgentSkillStoreError.disabled(record.entry.id) }
        return try load(
            record,
            maximumCharacters: max(512, min(maximumCharacters, 64_000)),
            triggerReason: triggerReason
        )
    }

    public func resolveMatches(
        userMessage: String,
        maximumMatches: Int = 2
    ) throws -> [ResolvedAgentSkill] {
        let normalizedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty else { return [] }

        let matches = try scan().compactMap { record -> (IndexedSkill, Double, String)? in
            let entry = record.entry
            guard entry.enabled else { return nil }
            var score = 0.0
            var reason = "User request matched skill description"
            if normalizedMessage.localizedStandardContains("$\(entry.id)") {
                score += 1.5
                reason = "User request explicitly matched skill id"
            } else if entry.id.count >= 3,
                      normalizedMessage.localizedStandardContains(entry.id) {
                score += 1.0
                reason = "User request matched skill id"
            }
            if entry.name.count >= 3,
               normalizedMessage.localizedStandardContains(entry.name) {
                score += 0.9
                reason = "User request matched skill name"
            }
            for phrase in candidatePhrases(entry.description)
            where normalizedMessage.localizedStandardContains(phrase) {
                score += 0.25
            }
            guard score > 0 else { return nil }
            return (record, min(score, 1.5), reason)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.entry.id < rhs.0.entry.id }
            return lhs.1 > rhs.1
        }
        .prefix(max(0, min(maximumMatches, 2)))

        return try matches.map { record, _, reason in
            try load(record, maximumCharacters: 12_000, triggerReason: reason)
        }
    }

    /// Changes the host-owned enablement registry. This API is intentionally
    /// not exposed as an Agent tool; enablement requires a trusted app surface.
    @discardableResult
    public func setEnabled(_ identifier: String, enabled: Bool) throws -> AgentSkillIndexEntry {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw AgentSkillStoreError.missingIdentifier }
        let record = try matchingRecord(
            identifier: normalized,
            in: scan(shouldRefreshProjection: false)
        )
        let previousRegistry = try readRegistry()
        var registry = previousRegistry
        var enabledIDs = Set(registry.enabledSkillIDs)
        if enabled {
            enabledIDs.insert(record.entry.id)
        } else {
            enabledIDs.remove(record.entry.id)
        }
        registry.enabledSkillIDs = enabledIDs.sorted()
        try writeRegistry(registry)
        do {
            let updated = try scan()
            guard let entry = updated.first(where: { $0.entry.id == record.entry.id })?.entry else {
                throw AgentSkillStoreError.notFound(record.entry.id)
            }
            return entry
        } catch {
            try? writeRegistry(previousRegistry)
            _ = try? scan()
            throw error
        }
    }

    /// Imports a user-selected skill into the host-only Control directory.
    /// Selecting a directory imports the complete package. Selecting SKILL.md
    /// imports only that file so choosing a loose file cannot copy unrelated
    /// siblings from the containing folder.
    @discardableResult
    public func importSkill(from sourceURL: URL) throws -> AgentSkillIndexEntry {
        let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try paths.prepare(fileManager: fileManager)
        let currentRecords = try scan(shouldRefreshProjection: false)
        guard currentRecords.count < maximumInstalledSkills else {
            throw AgentSkillStoreError.installedSkillLimitExceeded(maximumInstalledSkills)
        }

        let selection = try importSelection(for: sourceURL)
        try rejectProtectedImportSource(selection)
        if selection.copiesEntireDirectory {
            try validatePackage(at: selection.sourceRoot)
        } else {
            try validateRegularFile(selection.skillFile)
        }

        let document = try parse(selection.skillFile)
        guard Self.isAppleCompatible(document) else {
            throw AgentSkillStoreError.incompatibleSkill
        }
        let id = Self.sanitizedSkillID(
            document.frontmatter["name"] ?? selection.sourceRoot.lastPathComponent
        )
        guard Self.isSafeSkillID(id) else {
            throw AgentSkillStoreError.invalidImportedIdentifier
        }
        guard !currentRecords.contains(where: { $0.entry.id == id }) else {
            throw AgentSkillStoreError.alreadyInstalled(id)
        }

        let destination = paths.authoritativeSkillsDirectory
            .appending(path: id, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw AgentSkillStoreError.alreadyInstalled(id)
        }
        let staging = paths.authoritativeSkillsDirectory.appending(
            path: ".import-staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var committedURL: URL?
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: staging)
                if let committedURL {
                    try? fileManager.removeItem(at: committedURL)
                }
            }
        }

        if selection.copiesEntireDirectory {
            try copyImportedPackage(from: selection.sourceRoot, to: staging)
        } else {
            try fileManager.copyItem(
                at: selection.skillFile,
                to: staging.appending(path: "SKILL.md", directoryHint: .notDirectory)
            )
        }
        try validatePackage(at: staging)
        try fileManager.moveItem(at: staging, to: destination)
        committedURL = destination

        do {
            let records = try scan()
            guard let imported = records.first(where: { $0.entry.id == id })?.entry else {
                throw AgentSkillStoreError.notFound(id)
            }
            completed = true
            return imported
        } catch {
            try? fileManager.removeItem(at: destination)
            committedURL = nil
            _ = try? scan()
            throw error
        }
    }

    /// Removes only the selected host-authoritative package. Workspace
    /// projections are regenerated from the remaining enabled registry.
    public func delete(_ identifier: String) throws {
        let records = try scan(shouldRefreshProjection: false)
        let record = try matchingRecord(identifier: identifier, in: records)
        let canonicalAuthority = paths.authoritativeSkillsDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonicalRoot = record.authoritativeRoot
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard canonicalRoot.pathComponents.starts(with: canonicalAuthority.pathComponents),
              canonicalRoot.pathComponents.count > canonicalAuthority.pathComponents.count else {
            throw AgentSkillStoreError.invalidAuthoritativeSkillRoot
        }
        guard !records.contains(where: { candidate in
            candidate.entry.id != record.entry.id
                && candidate.authoritativeRoot.standardizedFileURL.pathComponents.starts(
                    with: record.authoritativeRoot.standardizedFileURL.pathComponents
                )
        }) else {
            throw AgentSkillStoreError.skillContainsNestedSkills(record.entry.id)
        }

        let previousRegistry = try readRegistry()
        let backup = paths.authoritativeSkillsDirectory.appending(
            path: ".delete-staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.moveItem(at: record.authoritativeRoot, to: backup)
        do {
            var registry = previousRegistry
            registry.enabledSkillIDs.removeAll { $0 == record.entry.id }
            try writeRegistry(registry)
            _ = try scan()
            try? fileManager.removeItem(at: backup)
        } catch {
            try? writeRegistry(previousRegistry)
            if fileManager.fileExists(atPath: record.authoritativeRoot.path) {
                try? fileManager.removeItem(at: record.authoritativeRoot)
            }
            try? fileManager.moveItem(at: backup, to: record.authoritativeRoot)
            _ = try? scan()
            throw error
        }
    }

    private func importSelection(for sourceURL: URL) throws -> ImportSelection {
        let source = sourceURL.standardizedFileURL
        let values = try source.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw AgentSkillStoreError.symbolicLinkNotAllowed(source.lastPathComponent)
        }
        if values.isDirectory == true {
            let skillFile = source.appending(path: "SKILL.md", directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: skillFile.path) else {
                throw AgentSkillStoreError.missingImportedSkillFile
            }
            return ImportSelection(
                sourceRoot: source,
                skillFile: skillFile,
                copiesEntireDirectory: true
            )
        }
        guard values.isRegularFile == true,
              source.lastPathComponent == "SKILL.md" else {
            throw AgentSkillStoreError.invalidImportSelection(source.lastPathComponent)
        }
        return ImportSelection(
            sourceRoot: source.deletingLastPathComponent(),
            skillFile: source,
            copiesEntireDirectory: false
        )
    }

    private func rejectProtectedImportSource(_ selection: ImportSelection) throws {
        let canonicalSource = selection.skillFile
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonicalProjection = paths.skillsDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard !canonicalSource.pathComponents.starts(with: canonicalProjection.pathComponents) else {
            throw AgentSkillStoreError.workspaceProjectionCannotBeImported
        }

        let canonicalSourceRoot = selection.sourceRoot
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonicalAuthority = paths.authoritativeSkillsDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard !canonicalSourceRoot.pathComponents.starts(with: canonicalAuthority.pathComponents) else {
            throw AgentSkillStoreError.authoritativeSkillCannotBeReimported
        }
    }

    private func validatePackage(at root: URL) throws {
        let rootValues = try root.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw AgentSkillStoreError.invalidImportSelection(root.lastPathComponent)
        }
        let canonicalRoot = root.standardizedFileURL
        let expectedSkillFile = canonicalRoot.appending(
            path: "SKILL.md",
            directoryHint: .notDirectory
        ).standardizedFileURL
        guard fileManager.fileExists(atPath: expectedSkillFile.path) else {
            throw AgentSkillStoreError.missingImportedSkillFile
        }
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else {
            throw AgentSkillStoreError.invalidImportSelection(root.lastPathComponent)
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            let itemURL = item.standardizedFileURL
            guard itemURL.pathComponents.starts(with: canonicalRoot.pathComponents) else {
                throw AgentSkillStoreError.invalidImportSelection(item.lastPathComponent)
            }
            let values = try itemURL.resourceValues(forKeys: [
                .fileSizeKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                throw AgentSkillStoreError.symbolicLinkNotAllowed(item.lastPathComponent)
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw AgentSkillStoreError.invalidImportedItem(item.lastPathComponent)
            }
            if itemURL.lastPathComponent == "SKILL.md", itemURL != expectedSkillFile {
                throw AgentSkillStoreError.nestedSkillFileNotAllowed
            }
            let bytes = Int64(fileSize)
            guard bytes <= importLimits.maximumFileBytes else {
                throw AgentSkillStoreError.importedFileTooLarge(
                    item.lastPathComponent,
                    importLimits.maximumFileBytes
                )
            }
            fileCount += 1
            guard fileCount <= importLimits.maximumFileCount else {
                throw AgentSkillStoreError.importFileCountExceeded(importLimits.maximumFileCount)
            }
            let (newTotal, overflow) = totalBytes.addingReportingOverflow(bytes)
            guard !overflow, newTotal <= importLimits.maximumTotalBytes else {
                throw AgentSkillStoreError.importTotalBytesExceeded(importLimits.maximumTotalBytes)
            }
            totalBytes = newTotal
        }
        try validateRegularFile(expectedSkillFile)
    }

    private func validateRegularFile(_ fileURL: URL) throws {
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AgentSkillStoreError.invalidSkillFile(fileURL.lastPathComponent)
        }
        guard let size = values.fileSize else {
            throw AgentSkillStoreError.invalidSkillFile(fileURL.lastPathComponent)
        }
        guard size <= importLimits.maximumSkillFileBytes else {
            throw AgentSkillStoreError.skillFileTooLarge(
                fileURL.lastPathComponent,
                importLimits.maximumSkillFileBytes
            )
        }
        let bytes = Int64(size)
        guard bytes <= importLimits.maximumFileBytes else {
            throw AgentSkillStoreError.importedFileTooLarge(
                fileURL.lastPathComponent,
                importLimits.maximumFileBytes
            )
        }
        guard bytes <= importLimits.maximumTotalBytes else {
            throw AgentSkillStoreError.importTotalBytesExceeded(
                importLimits.maximumTotalBytes
            )
        }
    }

    private func copyImportedPackage(from sourceRoot: URL, to destinationRoot: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else {
            throw AgentSkillStoreError.invalidImportSelection(sourceRoot.lastPathComponent)
        }
        let sourceComponents = sourceRoot.standardizedFileURL.pathComponents
        while let source = enumerator.nextObject() as? URL {
            let values = try source.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                throw AgentSkillStoreError.symbolicLinkNotAllowed(source.lastPathComponent)
            }
            let sourcePathComponents = source.standardizedFileURL.pathComponents
            guard sourcePathComponents.starts(with: sourceComponents) else {
                throw AgentSkillStoreError.invalidImportedItem(source.lastPathComponent)
            }
            let relativeComponents = sourcePathComponents.dropFirst(sourceComponents.count)
            let destination = relativeComponents.reduce(destinationRoot) { partial, component in
                partial.appending(path: component)
            }
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: destination)
            } else {
                throw AgentSkillStoreError.invalidImportedItem(source.lastPathComponent)
            }
        }
    }

    private func scan(shouldRefreshProjection: Bool = true) throws -> [IndexedSkill] {
        try paths.prepare(fileManager: fileManager)
        let enabledSkillIDs = Set(try readRegistry().enabledSkillIDs)
        guard let enumerator = fileManager.enumerator(
            at: paths.authoritativeSkillsDirectory,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            if shouldRefreshProjection { try refreshProjection(with: []) }
            return []
        }

        var skillFiles: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL,
              skillFiles.count < maximumInstalledSkills {
            let values = try fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard fileURL.lastPathComponent == "SKILL.md",
                  values.isRegularFile == true else {
                continue
            }
            skillFiles.append(fileURL)
        }

        let records = try skillFiles
            .sorted { $0.path < $1.path }
            .compactMap { try indexEntry(for: $0, enabledSkillIDs: enabledSkillIDs) }
        var seenIDs = Set<String>()
        for record in records where !seenIDs.insert(record.entry.id).inserted {
            throw AgentSkillStoreError.duplicateIdentifier(record.entry.id)
        }
        if shouldRefreshProjection { try refreshProjection(with: records) }
        return records.sorted {
            $0.entry.name.localizedStandardCompare($1.entry.name) == .orderedAscending
        }
    }

    private func indexEntry(
        for skillFile: URL,
        enabledSkillIDs: Set<String>
    ) throws -> IndexedSkill? {
        let document = try parse(skillFile)
        let authoritativeRoot = skillFile.deletingLastPathComponent()
        let compatibility = document.frontmatter["compatibility"]
        let description = document.frontmatter["description"]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        guard Self.isAppleCompatible(document) else {
            return nil
        }
        let id = Self.sanitizedSkillID(
            document.frontmatter["name"] ?? authoritativeRoot.lastPathComponent
        )
        guard Self.isSafeSkillID(id) else { return nil }
        let configuredName = document.frontmatter["name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectedRoot = paths.skillsDirectory
            .appending(path: id, directoryHint: .isDirectory)
        let projectedSkillFile = projectedRoot.appending(path: "SKILL.md")
        let entry = AgentSkillIndexEntry(
            id: id,
            name: configuredName.isEmpty ? id : configuredName,
            description: description,
            compatibility: compatibility,
            metadata: parseIndentedMetadata(document.frontmatter["metadata"] ?? ""),
            rootPath: try resourceProtocol.shellPath(for: projectedRoot),
            skillFilePath: try resourceProtocol.shellPath(for: projectedSkillFile),
            hasScripts: isDirectory(authoritativeRoot.appending(path: "scripts", directoryHint: .isDirectory)),
            hasReferences: isDirectory(authoritativeRoot.appending(path: "references", directoryHint: .isDirectory)),
            hasAssets: isDirectory(authoritativeRoot.appending(path: "assets", directoryHint: .isDirectory)),
            hasEvals: isDirectory(authoritativeRoot.appending(path: "evals", directoryHint: .isDirectory)),
            enabled: enabledSkillIDs.contains(id)
        )
        return IndexedSkill(
            entry: entry,
            authoritativeRoot: authoritativeRoot,
            authoritativeSkillFile: skillFile
        )
    }

    private func load(
        _ record: IndexedSkill,
        maximumCharacters: Int,
        triggerReason: String
    ) throws -> ResolvedAgentSkill {
        let entry = record.entry
        let document = try parse(record.authoritativeSkillFile)
        let referencesRoot = record.authoritativeRoot
            .appending(path: "references", directoryHint: .isDirectory)
        let projectedReferencesRoot = paths.skillsDirectory
            .appending(path: entry.id, directoryHint: .isDirectory)
            .appending(path: "references", directoryHint: .isDirectory)
        let references: [String] = if isDirectory(referencesRoot) {
            try fileManager.contentsOfDirectory(
                at: referencesRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values?.isRegularFile == true && values?.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(32)
            .map { reference in
                try resourceProtocol.shellPath(
                    for: projectedReferencesRoot.appending(path: reference.lastPathComponent)
                )
            }
        } else {
            []
        }
        let boundedBody = document.body.count <= maximumCharacters
            ? document.body
            : String(document.body.prefix(maximumCharacters)) + "\n…[skill truncated]"
        return ResolvedAgentSkill(
            entry: entry,
            frontmatter: document.frontmatter,
            bodyMarkdown: boundedBody,
            referencePaths: references,
            scriptsPath: entry.hasScripts ? entry.rootPath + "/scripts" : nil,
            assetsPath: entry.hasAssets ? entry.rootPath + "/assets" : nil,
            triggerReason: triggerReason
        )
    }

    private func matchingRecord(
        identifier: String,
        in records: [IndexedSkill]
    ) throws -> IndexedSkill {
        if let exact = records.first(where: {
            $0.entry.id.caseInsensitiveCompare(identifier) == .orderedSame
                || $0.entry.name.caseInsensitiveCompare(identifier) == .orderedSame
                || $0.entry.skillFilePath == identifier
                || $0.entry.rootPath == identifier
        }) {
            return exact
        }
        let partial = records.filter {
            $0.entry.id.localizedStandardContains(identifier)
                || $0.entry.name.localizedStandardContains(identifier)
        }
        guard partial.count <= 1 else { throw AgentSkillStoreError.ambiguousIdentifier(identifier) }
        guard let match = partial.first else { throw AgentSkillStoreError.notFound(identifier) }
        return match
    }

    private func parse(_ fileURL: URL) throws -> ParsedDocument {
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AgentSkillStoreError.invalidSkillFile(fileURL.lastPathComponent)
        }
        guard let size = values.fileSize, size <= importLimits.maximumSkillFileBytes else {
            throw AgentSkillStoreError.skillFileTooLarge(
                fileURL.lastPathComponent,
                importLimits.maximumSkillFileBytes
            )
        }
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        guard raw.hasPrefix("---") else {
            return ParsedDocument(frontmatter: [:], body: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        guard let closingIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            return ParsedDocument(frontmatter: [:], body: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let frontmatter = parseFrontmatter(lines[1..<closingIndex].map(String.init))
        let body = lines[lines.index(after: closingIndex)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedDocument(frontmatter: frontmatter, body: body)
    }

    private func parseFrontmatter(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
                index += 1
                continue
            }
            if value.isEmpty || value == ">" || value == "|" {
                var continuation: [String] = []
                index += 1
                while index < lines.count,
                      lines[index].hasPrefix("  ") || lines[index].hasPrefix("\t") || lines[index].isEmpty {
                    if !lines[index].isEmpty {
                        continuation.append(lines[index].trimmingCharacters(in: .whitespaces))
                    }
                    index += 1
                }
                value = continuation.joined(separator: value == ">" ? " " : "\n")
            } else {
                index += 1
            }
            result[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return result
    }

    private func parseIndentedMetadata(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private func readRegistry() throws -> SkillRegistry {
        guard fileManager.fileExists(atPath: paths.skillRegistryFile.path) else {
            return SkillRegistry()
        }
        let values = try paths.skillRegistryFile.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= maximumRegistryBytes else {
            throw AgentSkillStoreError.invalidRegistry
        }
        let registry = try JSONDecoder().decode(
            SkillRegistry.self,
            from: Data(contentsOf: paths.skillRegistryFile)
        )
        guard registry.version == 1 else { throw AgentSkillStoreError.invalidRegistry }
        let normalizedIDs = registry.enabledSkillIDs.map(Self.sanitizedSkillID)
        guard normalizedIDs.count == Set(normalizedIDs).count,
              normalizedIDs.allSatisfy(Self.isSafeSkillID),
              zip(normalizedIDs, registry.enabledSkillIDs).allSatisfy({ pair in
                  pair.0 == pair.1
              }) else {
            throw AgentSkillStoreError.invalidRegistry
        }
        return registry
    }

    private func writeRegistry(_ registry: SkillRegistry) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(registry)
        guard data.count <= maximumRegistryBytes else {
            throw AgentSkillStoreError.invalidRegistry
        }
        try data.write(to: paths.skillRegistryFile, options: .atomic)
    }

    private func refreshProjection(with records: [IndexedSkill]) throws {
        do {
            let destination = try workspaceFileSystem.parse(".omnibot/skills")
            let sources = records
                .filter(\.entry.enabled)
                .map { record in
                    WorkspaceDescriptorFileSystem.DirectoryProjectionSource(
                        sourceRoot: record.authoritativeRoot,
                        destinationComponents: [record.entry.id]
                    )
                }
            try workspaceFileSystem.replaceDirectoryAtomically(
                at: destination,
                with: sources,
                maximumFiles: maximumProjectionFiles,
                maximumBytes: maximumProjectionBytes
            )
        } catch is WorkspaceDescriptorFileSystem.HostWriteLimitError {
            throw AgentSkillStoreError.projectionLimitExceeded
        } catch {
            throw AgentSkillStoreError.invalidProjectionDirectory
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))
            .map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
    }

    private func candidatePhrases(_ description: String) -> [String] {
        let stopWords: Set<String> = [
            "and", "for", "from", "that", "the", "this", "use", "when", "with",
        ]
        return description
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 && !stopWords.contains($0.lowercased()) }
            .prefix(24)
            .map { $0 }
    }

    private static func isAppleCompatible(_ document: ParsedDocument) -> Bool {
        let compatibility = document.frontmatter["compatibility"] ?? ""
        let normalizedCompatibility = normalizedMarkerText(compatibility)
        let applePlatformMarkers = ["apple", "ios", "ipados", "macos", "watchos", "visionos"]
        if containsAndroidRuntimeMarker(compatibility)
            || (normalizedCompatibility.contains("android")
                && !applePlatformMarkers.contains(where: normalizedCompatibility.contains)) {
            return false
        }

        let metadata = document.frontmatter["metadata"] ?? ""
        if containsAndroidRuntimeMarker(metadata)
            || metadataDeclaresAndroidOnlyPlatform(metadata) {
            return false
        }

        let description = document.frontmatter["description"] ?? ""
        return !containsAndroidRuntimeMarker(description)
            && !containsAndroidRuntimeMarker(document.body)
    }

    private static func containsAndroidRuntimeMarker(_ value: String) -> Bool {
        let normalized = normalizedMarkerText(value)
        let markers = [
            "android only",
            "only android",
            "android exclusive",
            "only supports android",
            "requires android",
            "require android",
            "shizuku",
            "accessibilityservice",
            "仅限 android",
            "只支持 android",
            "需要 android",
            "依赖 android",
        ]
        return markers.contains(where: normalized.contains)
    }

    private static func metadataDeclaresAndroidOnlyPlatform(_ metadata: String) -> Bool {
        let platformKeys: Set<String> = [
            "os", "platform", "platforms", "runtime", "target", "targets",
        ]
        let applePlatformMarkers = ["apple", "ios", "ipados", "macos", "watchos", "visionos"]

        return metadata.split(whereSeparator: \Character.isNewline).contains { line in
            let normalized = normalizedMarkerText(String(line))
            let words = normalized.split(separator: " ").map(String.init)
            guard let key = words.first,
                  platformKeys.contains(key),
                  words.contains("android") else {
                return false
            }
            return !applePlatformMarkers.contains(where: words.contains)
        }
    }

    private static func normalizedMarkerText(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sanitizedSkillID(_ value: String) -> String {
        var result = ""
        var lastWasSeparator = false
        for character in value.lowercased() {
            if character.isLetter || character.isNumber || character == "." || character == "_" {
                result.append(character)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func isSafeSkillID(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 128
            && value != "."
            && value != ".."
            && !value.hasPrefix(".")
    }
}

nonisolated public enum AgentSkillStoreError: LocalizedError, Sendable {
    case missingIdentifier
    case notFound(String)
    case ambiguousIdentifier(String)
    case duplicateIdentifier(String)
    case disabled(String)
    case invalidRegistry
    case invalidSkillFile(String)
    case skillFileTooLarge(String, Int)
    case invalidImportSelection(String)
    case missingImportedSkillFile
    case invalidImportedItem(String)
    case symbolicLinkNotAllowed(String)
    case nestedSkillFileNotAllowed
    case workspaceProjectionCannotBeImported
    case authoritativeSkillCannotBeReimported
    case incompatibleSkill
    case invalidImportedIdentifier
    case alreadyInstalled(String)
    case installedSkillLimitExceeded(Int)
    case importedFileTooLarge(String, Int64)
    case importFileCountExceeded(Int)
    case importTotalBytesExceeded(Int64)
    case invalidAuthoritativeSkillRoot
    case skillContainsNestedSkills(String)
    case projectionLimitExceeded
    case invalidProjectionDirectory

    public var errorDescription: String? {
        switch self {
        case .missingIdentifier: "A skill id, name, or path is required."
        case let .notFound(value): "Installed skill not found: \(value)"
        case let .ambiguousIdentifier(value): "Skill identifier is ambiguous: \(value)"
        case let .duplicateIdentifier(value): "Multiple authoritative skills use the same id: \(value)"
        case let .disabled(value): "Skill is disabled: \(value)"
        case .invalidRegistry: "The host skill enablement registry is invalid."
        case let .invalidSkillFile(value): "Invalid SKILL.md file: \(value)"
        case let .skillFileTooLarge(value, limit):
            "SKILL.md exceeds the \(limit)-byte limit: \(value)"
        case let .invalidImportSelection(value):
            "请选择包含 SKILL.md 的目录，或直接选择 SKILL.md 文件：\(value)"
        case .missingImportedSkillFile:
            "所选目录的顶层没有 SKILL.md。"
        case let .invalidImportedItem(value):
            "技能包包含不支持的文件类型：\(value)"
        case let .symbolicLinkNotAllowed(value):
            "技能包不允许包含符号链接：\(value)"
        case .nestedSkillFileNotAllowed:
            "一个导入包只能包含顶层的 SKILL.md。"
        case .workspaceProjectionCannotBeImported:
            "工作区中的 Skills 投影不是权威来源，不能重新导入。"
        case .authoritativeSkillCannotBeReimported:
            "该技能已经位于 OmniBot 的权威目录中。"
        case .incompatibleSkill:
            "该技能声明为 Android 专用，无法导入 Apple 版本。"
        case .invalidImportedIdentifier:
            "SKILL.md 未提供可用的技能名称。"
        case let .alreadyInstalled(value):
            "技能已安装：\(value)"
        case let .installedSkillLimitExceeded(limit):
            "已达到 \(limit) 个已安装技能的上限。"
        case let .importedFileTooLarge(value, limit):
            "技能文件超过 \(limit) 字节上限：\(value)"
        case let .importFileCountExceeded(limit):
            "技能包文件数量超过 \(limit) 个上限。"
        case let .importTotalBytesExceeded(limit):
            "技能包总大小超过 \(limit) 字节上限。"
        case .invalidAuthoritativeSkillRoot:
            "技能目录不在受保护的 Control 权威目录中。"
        case let .skillContainsNestedSkills(value):
            "技能 \(value) 包含嵌套技能，无法单独安全删除。"
        case .projectionLimitExceeded:
            "Enabled skill projections exceed the configured file or byte limit."
        case .invalidProjectionDirectory:
            "The workspace skill projection directory has been replaced or redirected."
        }
    }
}
