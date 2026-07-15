import Foundation

extension OmniAgentToolExecutor {
    func readFile(_ arguments: OmniToolArguments) throws -> AgentToolExecutionResult {
        let suppliedPath = try arguments.requiredString("path", maximumLength: 4_096)
        let path = try descriptorFileSystem.parse(suppliedPath)
        let offset = try arguments.integer(
            "offset_bytes",
            default: 0,
            range: 0...Int.max
        ) ?? 0
        let requestedMaximum = try arguments.integer(
            "max_bytes",
            default: limits.maximumReadableFileBytes,
            range: 1...limits.maximumReadableFileBytes
        ) ?? limits.maximumReadableFileBytes
        let encoding = try arguments.optionalString("encoding", default: "utf8") ?? "utf8"
        guard encoding == "utf8" || encoding == "base64" else {
            throw OmniAgentToolError(
                "Invalid parameter 'encoding': expected 'utf8' or 'base64'."
            )
        }

        let result = try descriptorFileSystem.readRegularFile(
            at: path,
            offset: offset,
            maximumBytes: requestedMaximum
        )
        guard result.fileSize <= limits.maximumReadableFileBytes else {
            throw OmniAgentToolError(
                "File '\(suppliedPath)' is \(result.fileSize) bytes, exceeding the \(limits.maximumReadableFileBytes)-byte read limit."
            )
        }

        let content: String
        if encoding == "base64" {
            content = result.data.base64EncodedString()
        } else {
            guard let decoded = String(data: result.data, encoding: .utf8) else {
                throw OmniAgentToolError(
                    "File '\(suppliedPath)' is not valid UTF-8 in the requested byte range; retry with encoding='base64'."
                )
            }
            content = decoded
        }
        let safeOffset = min(offset, result.fileSize)
        let returnedEnd = safeOffset + result.data.count
        let artifact = try fileArtifact(for: path, sourceTool: "file_read")
        return AgentToolExecutionResult(
            content: content,
            metadata: [
                "path": .string(path.displayPath),
                "fileSizeBytes": .number(Double(result.fileSize)),
                "offsetBytes": .number(Double(safeOffset)),
                "returnedBytes": .number(Double(result.data.count)),
                "truncated": .bool(returnedEnd < result.fileSize),
                "encoding": .string(encoding),
            ],
            artifacts: [artifact],
            workspaceID: "shared"
        )
    }

    func writeFile(_ arguments: OmniToolArguments) throws -> AgentToolExecutionResult {
        let suppliedPath = try arguments.requiredString("path", maximumLength: 4_096)
        let content = try arguments.requiredString("content")
        let mode = try arguments.optionalString("mode", default: "overwrite") ?? "overwrite"
        guard mode == "overwrite" || mode == "append" else {
            throw OmniAgentToolError(
                "Invalid parameter 'mode': expected 'overwrite' or 'append'."
            )
        }
        let createParents = try arguments.bool("create_parent_directories", default: true)
        let data = Data(content.utf8)
        guard data.count <= limits.maximumWritableFileBytes else {
            throw OmniAgentToolError(
                "Write content is \(data.count) bytes, exceeding the \(limits.maximumWritableFileBytes)-byte limit."
            )
        }

        let path = try descriptorFileSystem.parse(suppliedPath)
        let finalSize = try descriptorFileSystem.atomicallyWrite(
            data,
            to: path,
            createParentDirectories: createParents,
            appending: mode == "append",
            maximumBytes: limits.maximumWritableFileBytes
        )
        let artifact = try fileArtifact(for: path, sourceTool: "file_write")
        return AgentToolExecutionResult(
            content: "Wrote \(data.count) bytes to \(path.displayPath).",
            metadata: [
                "path": .string(path.displayPath),
                "bytesWritten": .number(Double(data.count)),
                "fileSizeBytes": .number(Double(finalSize)),
                "mode": .string(mode),
            ],
            artifacts: [artifact],
            workspaceID: "shared"
        )
    }

    func editFile(_ arguments: OmniToolArguments) throws -> AgentToolExecutionResult {
        let suppliedPath = try arguments.requiredString("path", maximumLength: 4_096)
        let oldText = try arguments.requiredString("old_text")
        let newText = try arguments.requiredString("new_text")
        let replaceAll = try arguments.bool("replace_all", default: false)
        guard !oldText.isEmpty else {
            throw OmniAgentToolError("Parameter 'old_text' must not be empty.")
        }

        let path = try descriptorFileSystem.parse(suppliedPath)
        let originalData = try descriptorFileSystem.readEntireRegularFile(
            at: path,
            maximumBytes: limits.maximumReadableFileBytes
        )
        guard let original = String(data: originalData, encoding: .utf8) else {
            throw OmniAgentToolError("File '\(suppliedPath)' is not valid UTF-8.")
        }
        let occurrenceCount = original.components(separatedBy: oldText).count - 1
        guard occurrenceCount > 0 else {
            throw OmniAgentToolError(
                "The requested old_text was not found in '\(suppliedPath)'."
            )
        }
        if !replaceAll, occurrenceCount > 1 {
            throw OmniAgentToolError(
                "old_text occurs \(occurrenceCount) times in '\(suppliedPath)'; set replace_all=true or provide a unique fragment."
            )
        }

        let edited: String
        let replacements: Int
        if replaceAll {
            edited = original.replacing(oldText, with: newText)
            replacements = occurrenceCount
        } else if original.range(of: oldText) != nil {
            edited = original.replacing(oldText, with: newText, maxReplacements: 1)
            replacements = 1
        } else {
            throw OmniAgentToolError("The requested old_text was not found.")
        }
        let editedData = Data(edited.utf8)
        guard editedData.count <= limits.maximumWritableFileBytes else {
            throw OmniAgentToolError(
                "Edited file would exceed the \(limits.maximumWritableFileBytes)-byte limit."
            )
        }
        _ = try descriptorFileSystem.atomicallyWrite(
            editedData,
            to: path,
            createParentDirectories: false,
            appending: false,
            maximumBytes: limits.maximumWritableFileBytes
        )
        let artifact = try fileArtifact(for: path, sourceTool: "file_edit")
        return AgentToolExecutionResult(
            content: "Edited \(path.displayPath); applied \(replacements) replacement(s).",
            metadata: [
                "path": .string(path.displayPath),
                "replacements": .number(Double(replacements)),
                "fileSizeBytes": .number(Double(editedData.count)),
            ],
            artifacts: [artifact],
            workspaceID: "shared"
        )
    }

    func listFiles(_ arguments: OmniToolArguments) throws -> AgentToolExecutionResult {
        let suppliedPath = try arguments.optionalString(
            "path",
            default: ".",
            maximumLength: 4_096
        ) ?? "."
        let recursive = try arguments.bool("recursive", default: false)
        let requestedMaximum = try arguments.integer(
            "max_entries",
            default: limits.maximumListEntries,
            range: 1...limits.maximumListEntries
        ) ?? limits.maximumListEntries
        let path = try descriptorFileSystem.parse(suppliedPath)
        let metadata = try descriptorFileSystem.metadata(for: path)
        guard metadata.kind == .directory else {
            throw OmniAgentToolError("Path '\(suppliedPath)' is not a directory.")
        }

        let listing = try descriptorFileSystem.list(
            path,
            recursive: recursive,
            maximumEntries: requestedMaximum
        )
        var lines = listing.entries.map { entry in
            let size = entry.metadata.kind == .symbolicLink
                ? "-"
                : String(entry.metadata.size)
            return "\(entry.metadata.kind.rawValue)\t\(size)\t\(entry.path.displayPath)"
        }
        if listing.truncated {
            lines.append("[listing truncated at \(requestedMaximum) entries]")
        }
        return AgentToolExecutionResult(
            content: lines.isEmpty ? "(empty directory)" : lines.joined(separator: "\n"),
            metadata: [
                "path": .string(path.displayPath),
                "entryCount": .number(Double(listing.entries.count)),
                "truncated": .bool(listing.truncated),
                "recursive": .bool(recursive),
            ]
        )
    }

    func searchFiles(_ arguments: OmniToolArguments) throws -> AgentToolExecutionResult {
        let suppliedPath = try arguments.optionalString(
            "path",
            default: ".",
            maximumLength: 4_096
        ) ?? "."
        let query = try arguments.requiredString("query", maximumLength: 8_192)
        guard !query.isEmpty else {
            throw OmniAgentToolError("Parameter 'query' must not be empty.")
        }
        let caseSensitive = try arguments.bool("case_sensitive", default: false)
        let requestedMaximum = try arguments.integer(
            "max_results",
            default: limits.maximumSearchResults,
            range: 1...limits.maximumSearchResults
        ) ?? limits.maximumSearchResults
        let path = try descriptorFileSystem.parse(suppliedPath)
        let needle = caseSensitive ? query : query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        var matches: [String] = []
        let search = try descriptorFileSystem.search(
            path,
            maximumFiles: limits.maximumSearchFiles,
            maximumFileBytes: limits.maximumReadableFileBytes
        ) { filePath, data in
            guard let contents = String(data: data, encoding: .utf8) else { return false }
            for (index, line) in contents.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).enumerated() {
                let haystack = caseSensitive
                    ? String(line)
                    : String(line).folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                guard haystack.contains(needle) else { continue }
                matches.append("\(filePath.displayPath):\(index + 1): \(String(line.prefix(500)))")
                if matches.count >= requestedMaximum { return true }
            }
            return false
        }
        return AgentToolExecutionResult(
            content: matches.isEmpty ? "No matches found." : matches.joined(separator: "\n"),
            metadata: [
                "query": .string(query),
                "matchCount": .number(Double(matches.count)),
                "filesScanned": .number(Double(search.filesScanned)),
                "truncated": .bool(search.truncated || matches.count >= requestedMaximum),
            ]
        )
    }

    func statFile(_ arguments: OmniToolArguments) throws -> AgentToolExecutionResult {
        let suppliedPath = try arguments.requiredString("path", maximumLength: 4_096)
        let path = try descriptorFileSystem.parse(suppliedPath)
        let metadata = try descriptorFileSystem.metadata(for: path)
        let artifacts: [AgentArtifact] = if metadata.kind == .regular {
            [try fileArtifact(for: path, sourceTool: "file_stat")]
        } else {
            []
        }
        return AgentToolExecutionResult(
            content: "\(path.displayPath) is a \(metadata.kind.rawValue) (\(metadata.size) bytes).",
            metadata: [
                "path": .string(path.displayPath),
                "type": .string(metadata.kind.rawValue),
                "sizeBytes": .number(Double(metadata.size)),
                "permissions": .string(String(metadata.permissions, radix: 8)),
                "modifiedAt": .string(iso8601String(metadata.modifiedAt)),
                "createdAt": .string(iso8601String(metadata.createdAt)),
            ],
            artifacts: artifacts,
            workspaceID: "shared"
        )
    }

    func moveFile(_ arguments: OmniToolArguments) throws -> AgentToolExecutionResult {
        let sourcePath = try arguments.requiredString("source", maximumLength: 4_096)
        let destinationPath = try arguments.requiredString("destination", maximumLength: 4_096)
        let overwrite = try arguments.bool("overwrite", default: false)
        let source = try descriptorFileSystem.parse(sourcePath)
        let destination = try descriptorFileSystem.parse(destinationPath)
        let overwroteExisting = try descriptorFileSystem.move(
            from: source,
            to: destination,
            overwrite: overwrite
        )
        let destinationMetadata = try descriptorFileSystem.metadata(for: destination)
        let artifacts: [AgentArtifact] = if destinationMetadata.kind == .regular {
            [try fileArtifact(for: destination, sourceTool: "file_move")]
        } else {
            []
        }
        return AgentToolExecutionResult(
            content: "Moved \(sourcePath) to \(destination.displayPath).",
            metadata: [
                "source": .string(sourcePath),
                "destination": .string(destination.displayPath),
                "overwroteExisting": .bool(overwroteExisting),
            ],
            artifacts: artifacts,
            workspaceID: "shared"
        )
    }

    private func fileArtifact(
        for path: WorkspaceDescriptorFileSystem.RelativePath,
        sourceTool: String
    ) throws -> AgentArtifact {
        let fileURL = path.components.reduce(paths.root) { partial, component in
            partial.appending(path: component)
        }
        return try resourceProtocol.artifact(for: fileURL, sourceTool: sourceTool)
    }

    private func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
