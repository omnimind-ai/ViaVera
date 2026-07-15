import Darwin
import Foundation

/// Descriptor-relative filesystem access rooted at the shared workspace.
///
/// Every operation opens the workspace root afresh, then walks each directory
/// component with `openat(O_DIRECTORY | O_NOFOLLOW)`. No operation resolves a
/// path and later reopens it by absolute name, which closes the symlink-swap
/// race between validation and I/O.
nonisolated struct WorkspaceDescriptorFileSystem: Sendable {
    nonisolated struct DirectoryProjectionSource: Sendable {
        let sourceRoot: URL
        let destinationComponents: [String]

        init(sourceRoot: URL, destinationComponents: [String]) {
            self.sourceRoot = sourceRoot
            self.destinationComponents = destinationComponents
        }
    }

    nonisolated enum HostWriteLimitError: Error, Sendable {
        case sourceFileTooLarge(maximumBytes: Int64)
        case projectionFileCountExceeded(maximum: Int)
        case projectionTotalBytesExceeded(maximum: Int64)
    }

    nonisolated struct RelativePath: Hashable, Sendable {
        let supplied: String
        let components: [String]

        var isRoot: Bool { components.isEmpty }
        var leafName: String? { components.last }
        var parentComponents: ArraySlice<String> { components.dropLast() }

        var displayPath: String {
            components.isEmpty ? "/workspace" : "/workspace/" + components.joined(separator: "/")
        }

        func appending(_ component: String) -> RelativePath {
            RelativePath(supplied: supplied, components: components + [component])
        }
    }

    nonisolated enum ItemKind: String, Sendable {
        case regular = "file"
        case directory
        case symbolicLink = "symlink"
        case other
    }

    nonisolated struct ItemMetadata: Sendable {
        let kind: ItemKind
        let size: Int64
        let permissions: UInt16
        let device: Int32
        let inode: UInt64
        let modifiedAt: Date
        let createdAt: Date
    }

    nonisolated struct DirectoryEntry: Sendable {
        let path: RelativePath
        let metadata: ItemMetadata
    }

    let rootURL: URL

    init(paths: WorkspacePaths) {
        rootURL = paths.root.standardizedFileURL
    }

    func parse(_ suppliedPath: String) throws -> RelativePath {
        guard !suppliedPath.isEmpty else {
            throw OmniAgentToolError("Paths cannot be empty; use '.' or /workspace for the workspace root.")
        }
        guard !suppliedPath.contains("\0") else {
            throw OmniAgentToolError("Paths cannot contain NUL characters.")
        }

        let relative: String
        if suppliedPath == "." || suppliedPath == "/workspace" || suppliedPath == "/workspace/" {
            relative = ""
        } else if suppliedPath.hasPrefix("/workspace/") {
            relative = String(suppliedPath.dropFirst("/workspace/".count))
        } else if suppliedPath.hasPrefix("/") {
            throw OmniAgentToolError(
                "Absolute path '\(suppliedPath)' is not allowed; use /workspace/... instead."
            )
        } else {
            relative = suppliedPath
        }

        guard !relative.isEmpty || [".", "/workspace", "/workspace/"].contains(suppliedPath) else {
            throw OmniAgentToolError("Path '\(suppliedPath)' is empty below /workspace.")
        }
        if relative.isEmpty {
            return RelativePath(supplied: suppliedPath, components: [])
        }
        let rawComponents = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !rawComponents.contains(where: { $0.isEmpty }) else {
            throw OmniAgentToolError("Path '\(suppliedPath)' contains an empty component.")
        }

        var components: [String] = []
        components.reserveCapacity(rawComponents.count)
        for rawComponent in rawComponents {
            let component = String(rawComponent)
            guard component != ".", component != ".." else {
                throw OmniAgentToolError(
                    "Path '\(suppliedPath)' contains '\(component)'; traversal components are not allowed."
                )
            }
            guard !component.contains("\\") else {
                throw OmniAgentToolError(
                    "Path '\(suppliedPath)' contains a backslash, which is not supported by omnibot resource URIs."
                )
            }
            guard !containsUnsafePathScalars(component) else {
                throw OmniAgentToolError(
                    "Workspace paths cannot contain control or bidirectional formatting characters."
                )
            }
            guard component.utf8.count <= Int(NAME_MAX) else {
                throw OmniAgentToolError(
                    "A component in '\(suppliedPath)' exceeds the \(NAME_MAX)-byte filesystem limit."
                )
            }
            components.append(component)
        }
        return RelativePath(supplied: suppliedPath, components: components)
    }

    func requireLeaf(_ path: RelativePath) throws -> String {
        guard let leaf = path.leafName else {
            throw OmniAgentToolError("The workspace root cannot be used for this operation.")
        }
        return leaf
    }

    func createDirectory(_ path: RelativePath) throws {
        try withDirectoryDescriptor(components: path.components[...], create: true) { _ in }
    }

    /// Publishes a new regular file beneath an already descriptor-walked
    /// workspace directory. Both the directory walk and final rename are
    /// relative to open descriptors, so a guest cannot redirect the write by
    /// swapping a checked path for a symbolic link.
    func atomicallyWriteUnique(
        _ data: Data,
        in directory: RelativePath,
        preferredName: String,
        maximumBytes: Int
    ) throws -> RelativePath {
        guard data.count <= maximumBytes else {
            throw HostWriteLimitError.sourceFileTooLarge(
                maximumBytes: Int64(maximumBytes)
            )
        }
        let validatedName = try validatedFileName(preferredName)
        return try withDirectoryDescriptor(
            components: directory.components[...],
            create: true
        ) { parent in
            let publishedName = try publishUniqueFile(
                in: parent,
                preferredName: validatedName,
                mode: 0o644,
                path: directory.displayPath
            ) { destination in
                try writeAll(data, descriptor: destination, path: directory.displayPath)
            }
            return directory.appending(publishedName)
        }
    }

    /// Copies a user-selected regular file through an opened source descriptor
    /// and atomically publishes a uniquely named destination in the workspace.
    /// The source is bounded again while streaming so growth after its metadata
    /// check cannot bypass the limit.
    func copyRegularFileUnique(
        from sourceURL: URL,
        in directory: RelativePath,
        preferredName: String,
        maximumBytes: Int64
    ) throws -> RelativePath {
        let source = sourceURL.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return Darwin.open(pointer, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard source >= 0 else {
            throw posixError("open source file without following symlinks", path: sourceURL.path)
        }
        defer { Darwin.close(source) }

        let sourceMetadata = try metadata(descriptor: source, path: sourceURL.path)
        guard sourceMetadata.kind == .regular else {
            throw OmniAgentToolError("Source '\(sourceURL.lastPathComponent)' is not a regular file.")
        }
        guard sourceMetadata.size >= 0, sourceMetadata.size <= maximumBytes else {
            throw HostWriteLimitError.sourceFileTooLarge(maximumBytes: maximumBytes)
        }

        let validatedName = try validatedFileName(preferredName)
        return try withDirectoryDescriptor(
            components: directory.components[...],
            create: true
        ) { parent in
            let publishedName = try publishUniqueFile(
                in: parent,
                preferredName: validatedName,
                mode: 0o644,
                path: directory.displayPath
            ) { destination in
                guard Darwin.lseek(source, 0, SEEK_SET) >= 0 else {
                    throw posixError("rewind source file", path: sourceURL.path)
                }
                _ = try copyAll(
                    from: source,
                    to: destination,
                    maximumBytes: maximumBytes,
                    path: sourceURL.path
                )
            }
            return directory.appending(publishedName)
        }
    }

    /// Streams a workspace regular file from a pinned source descriptor into
    /// a host-only directory. Quick Look needs a stable URL and cannot consume
    /// an open descriptor directly, so callers use this to materialize a
    /// bounded snapshot without ever reopening the workspace path by name.
    func copyRegularFileToHostSnapshot(
        at sourcePath: RelativePath,
        destinationDirectory: URL,
        preferredName: String,
        maximumBytes: Int64
    ) throws -> URL {
        guard maximumBytes >= 0 else {
            throw OmniAgentToolError("Snapshot byte limits cannot be negative.")
        }
        let sourceName = try requireLeaf(sourcePath)
        let validatedName = try validatedFileName(preferredName)

        return try withDirectoryDescriptor(
            components: sourcePath.parentComponents,
            create: false
        ) { sourceParent in
            let source = try openRegularFile(
                at: sourceParent,
                name: sourceName,
                path: sourcePath.displayPath
            )
            defer { Darwin.close(source) }

            let sourceMetadata = try metadata(
                descriptor: source,
                path: sourcePath.displayPath
            )
            guard sourceMetadata.size >= 0,
                  sourceMetadata.size <= maximumBytes else {
                throw HostWriteLimitError.sourceFileTooLarge(maximumBytes: maximumBytes)
            }

            let destination = destinationDirectory.withUnsafeFileSystemRepresentation {
                pointer -> Int32 in
                guard let pointer else { return -1 }
                return Darwin.open(
                    pointer,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard destination >= 0 else {
                throw posixError("open host preview cache", path: "PreviewCache")
            }
            defer { Darwin.close(destination) }

            // Always add a UUID prefix. Preview snapshots must never replace a
            // prior preview even when two resources share the same leaf name.
            let snapshotName = try publishUniqueFile(
                in: destination,
                preferredName: collisionFileName(validatedName),
                mode: mode_t(0o600),
                path: "PreviewCache"
            ) { snapshot in
                guard Darwin.lseek(source, 0, SEEK_SET) >= 0 else {
                    throw posixError("rewind workspace preview source", path: sourcePath.displayPath)
                }
                _ = try copyAll(
                    from: source,
                    to: snapshot,
                    maximumBytes: maximumBytes,
                    path: sourcePath.displayPath
                )
            }
            return destinationDirectory.appending(
                path: snapshotName,
                directoryHint: .notDirectory
            )
        }
    }

    /// Removes an item without following a symbolic link in any component.
    func removeItem(_ path: RelativePath) throws {
        let leaf = try requireLeaf(path)
        try withDirectoryDescriptor(components: path.parentComponents, create: false) { parent in
            try removeEntryRecursively(at: parent, name: leaf, path: path.displayPath)
        }
    }

    /// Rebuilds and publishes a model-visible directory from host-authoritative
    /// source directories. The staging directory, all copied children, and the
    /// final swap stay relative to pinned descriptors for the complete
    /// transaction. Source paths are read-only host control inputs.
    func replaceDirectoryAtomically(
        at destination: RelativePath,
        with sources: [DirectoryProjectionSource],
        maximumFiles: Int,
        maximumBytes: Int64,
        skipsHiddenFiles: Bool = true
    ) throws {
        let destinationName = try requireLeaf(destination)
        _ = try validatedFileName(destinationName)
        try withDirectoryDescriptor(
            components: destination.parentComponents,
            create: true
        ) { parent in
            let stagingName = ".omnibot-projection-\(UUID().uuidString)"
            guard stagingName.withCString({ Darwin.mkdirat(parent, $0, mode_t(0o700)) }) == 0 else {
                throw posixError("create projection staging directory", path: destination.displayPath)
            }
            var didPublish = false
            defer {
                if !didPublish {
                    try? removeEntryRecursively(
                        at: parent,
                        name: stagingName,
                        path: destination.displayPath
                    )
                }
            }

            let staging = stagingName.withCString {
                Darwin.openat(
                    parent,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard staging >= 0 else {
                throw posixError("open projection staging directory", path: destination.displayPath)
            }
            defer { Darwin.close(staging) }

            var copiedFiles = 0
            var copiedBytes: Int64 = 0
            for source in sources {
                try copyProjectionSource(
                    source,
                    into: staging,
                    maximumFiles: maximumFiles,
                    maximumBytes: maximumBytes,
                    skipsHiddenFiles: skipsHiddenFiles,
                    copiedFiles: &copiedFiles,
                    copiedBytes: &copiedBytes
                )
            }

            guard Darwin.fchmod(staging, mode_t(0o755)) == 0 else {
                throw posixError("set projection directory permissions", path: destination.displayPath)
            }
            let openedStaging = try metadata(
                descriptor: staging,
                path: destination.displayPath
            )
            guard let namedStaging = try metadata(
                at: parent,
                name: stagingName,
                path: destination.displayPath
            ), namedStaging.kind == .directory,
                namedStaging.device == openedStaging.device,
                namedStaging.inode == openedStaging.inode else {
                throw OmniAgentToolError(
                    "The workspace projection staging directory changed before publication."
                )
            }

            let existing = try metadata(
                at: parent,
                name: destinationName,
                path: destination.displayPath
            )
            let renameResult = stagingName.withCString { stagingPointer in
                destinationName.withCString { destinationPointer in
                    Darwin.renameatx_np(
                        parent,
                        stagingPointer,
                        parent,
                        destinationPointer,
                        UInt32(existing == nil ? RENAME_EXCL : RENAME_SWAP)
                    )
                }
            }
            guard renameResult == 0 else {
                throw posixError("publish workspace projection", path: destination.displayPath)
            }
            didPublish = true
            _ = Darwin.fsync(parent)

            // After RENAME_SWAP the previous projection is now stored under the
            // staging name. Remove it relative to the same pinned parent and
            // never follow entries introduced by the guest.
            if existing != nil {
                try? removeEntryRecursively(
                    at: parent,
                    name: stagingName,
                    path: destination.displayPath
                )
            }
        }
    }

    func metadata(for path: RelativePath) throws -> ItemMetadata {
        if path.isRoot {
            return try withRootDescriptor { descriptor in
                try metadata(descriptor: descriptor, path: path.displayPath)
            }
        }
        let leaf = try requireLeaf(path)
        return try withDirectoryDescriptor(components: path.parentComponents, create: false) { parent in
            guard let metadata = try metadata(at: parent, name: leaf, path: path.displayPath) else {
                throw OmniAgentToolError("Path '\(path.supplied)' does not exist.")
            }
            return metadata
        }
    }

    func readRegularFile(
        at path: RelativePath,
        offset: Int = 0,
        maximumBytes: Int
    ) throws -> (data: Data, fileSize: Int) {
        let leaf = try requireLeaf(path)
        return try withDirectoryDescriptor(components: path.parentComponents, create: false) { parent in
            let descriptor = try openRegularFile(at: parent, name: leaf, path: path.displayPath)
            defer { Darwin.close(descriptor) }
            let metadata = try metadata(descriptor: descriptor, path: path.displayPath)
            guard metadata.size >= 0, metadata.size <= Int64(Int.max) else {
                throw OmniAgentToolError("File '\(path.supplied)' has an unsupported size.")
            }
            let fileSize = Int(metadata.size)
            let safeOffset = min(max(0, offset), fileSize)
            let count = min(maximumBytes, fileSize - safeOffset)
            return (
                try preadData(
                    descriptor: descriptor,
                    offset: safeOffset,
                    count: count,
                    path: path.displayPath
                ),
                fileSize
            )
        }
    }

    func readEntireRegularFile(
        at path: RelativePath,
        maximumBytes: Int
    ) throws -> Data {
        let result = try readRegularFile(at: path, maximumBytes: maximumBytes + 1)
        guard result.fileSize <= maximumBytes else {
            throw OmniAgentToolError(
                "File '\(path.supplied)' is \(result.fileSize) bytes, exceeding the \(maximumBytes)-byte limit."
            )
        }
        return result.data
    }

    /// Replaces `path` using a temporary regular file in the already-opened
    /// parent directory. A final symlink is rejected before mutation; if it is
    /// introduced after that check, `renameat` replaces the symlink itself and
    /// never follows its target.
    @discardableResult
    func atomicallyWrite(
        _ data: Data,
        to path: RelativePath,
        createParentDirectories: Bool,
        appending: Bool,
        maximumBytes: Int
    ) throws -> Int {
        let leaf = try requireLeaf(path)
        return try withDirectoryDescriptor(
            components: path.parentComponents,
            create: createParentDirectories
        ) { parent in
            let existing = try metadata(at: parent, name: leaf, path: path.displayPath)
            if let existing, existing.kind != .regular {
                throw OmniAgentToolError("Path '\(path.supplied)' is not a regular file.")
            }

            var finalData = data
            if appending, existing != nil {
                let source = try openRegularFile(at: parent, name: leaf, path: path.displayPath)
                defer { Darwin.close(source) }
                let existingMetadata = try metadata(descriptor: source, path: path.displayPath)
                guard existingMetadata.size >= 0,
                      existingMetadata.size <= Int64(maximumBytes),
                      existingMetadata.size <= Int64(Int.max) else {
                    throw OmniAgentToolError(
                        "Appending would exceed the \(maximumBytes)-byte file limit."
                    )
                }
                let existingData = try preadData(
                    descriptor: source,
                    offset: 0,
                    count: Int(existingMetadata.size),
                    path: path.displayPath
                )
                guard existingData.count <= maximumBytes - data.count else {
                    throw OmniAgentToolError(
                        "Appending would exceed the \(maximumBytes)-byte file limit."
                    )
                }
                finalData = existingData + data
            }
            guard finalData.count <= maximumBytes else {
                throw OmniAgentToolError(
                    "Write would exceed the \(maximumBytes)-byte file limit."
                )
            }

            let mode = mode_t(existing?.permissions ?? 0o644)
            let temporaryName = ".omnibot-write-\(UUID().uuidString)"
            let temporary = try openTemporaryFile(
                in: parent,
                name: temporaryName,
                mode: mode,
                path: path.displayPath
            )
            var renamed = false
            defer {
                Darwin.close(temporary)
                if !renamed {
                    temporaryName.withCString { _ = Darwin.unlinkat(parent, $0, 0) }
                }
            }

            try writeAll(finalData, descriptor: temporary, path: path.displayPath)
            guard Darwin.fsync(temporary) == 0 else {
                throw posixError("fsync", path: path.displayPath)
            }
            guard temporaryName.withCString({ temporaryPointer in
                leaf.withCString { leafPointer in
                    Darwin.renameat(parent, temporaryPointer, parent, leafPointer)
                }
            }) == 0 else {
                throw posixError("rename temporary file", path: path.displayPath)
            }
            renamed = true
            return finalData.count
        }
    }

    func move(
        from source: RelativePath,
        to destination: RelativePath,
        overwrite: Bool
    ) throws -> Bool {
        let sourceLeaf = try requireLeaf(source)
        let destinationLeaf = try requireLeaf(destination)
        guard source.components != destination.components else {
            throw OmniAgentToolError("Source and destination resolve to the same workspace item.")
        }
        guard !componentsOverlap(source.components, destination.components) else {
            throw OmniAgentToolError(
                "Source and destination cannot be ancestors or descendants of one another."
            )
        }

        return try withDirectoryDescriptor(components: source.parentComponents, create: false) { sourceParent in
            guard let sourceMetadata = try metadata(
                at: sourceParent,
                name: sourceLeaf,
                path: source.displayPath
            ) else {
                throw OmniAgentToolError("Path '\(source.supplied)' does not exist.")
            }
            guard sourceMetadata.kind != .symbolicLink else {
                throw OmniAgentToolError("Moving symbolic links is not supported.")
            }

            return try withDirectoryDescriptor(
                components: destination.parentComponents,
                create: true
            ) { destinationParent in
                let destinationMetadata = try metadata(
                    at: destinationParent,
                    name: destinationLeaf,
                    path: destination.displayPath
                )
                if let destinationMetadata {
                    guard !(sourceMetadata.device == destinationMetadata.device
                            && sourceMetadata.inode == destinationMetadata.inode) else {
                        throw OmniAgentToolError(
                            "Source and destination resolve to the same workspace item."
                        )
                    }
                    guard overwrite else {
                        throw OmniAgentToolError(
                            "Destination '\(destination.supplied)' already exists; set overwrite=true to replace it."
                        )
                    }
                    guard sourceMetadata.kind != .directory,
                          destinationMetadata.kind != .directory else {
                        throw OmniAgentToolError(
                            "Overwriting directories is not supported; move to a new destination or remove it explicitly."
                        )
                    }
                    guard sourceMetadata.kind == .regular,
                          destinationMetadata.kind == .regular else {
                        throw OmniAgentToolError(
                            "Overwrite is supported only when both source and destination are regular files."
                        )
                    }
                }

                guard sourceLeaf.withCString({ sourcePointer in
                    destinationLeaf.withCString { destinationPointer in
                        if overwrite {
                            Darwin.renameat(
                                sourceParent,
                                sourcePointer,
                                destinationParent,
                                destinationPointer
                            )
                        } else {
                            Darwin.renameatx_np(
                                sourceParent,
                                sourcePointer,
                                destinationParent,
                                destinationPointer,
                                UInt32(RENAME_EXCL)
                            )
                        }
                    }
                }) == 0 else {
                    throw posixError(
                        "move '\(source.displayPath)'",
                        path: destination.displayPath
                    )
                }
                return destinationMetadata != nil
            }
        }
    }

    func list(
        _ path: RelativePath,
        recursive: Bool,
        maximumEntries: Int
    ) throws -> (entries: [DirectoryEntry], truncated: Bool) {
        try withDirectoryDescriptor(components: path.components[...], create: false) { root in
            var entries: [DirectoryEntry] = []
            var truncated = false
            try enumerateDirectory(
                descriptor: root,
                path: path,
                recursive: recursive,
                maximumEntries: maximumEntries,
                entries: &entries,
                truncated: &truncated
            )
            return (entries, truncated)
        }
    }

    func search(
        _ path: RelativePath,
        maximumFiles: Int,
        maximumFileBytes: Int,
        body: (RelativePath, Data) throws -> Bool
    ) throws -> (filesScanned: Int, truncated: Bool) {
        let rootMetadata = try metadata(for: path)
        if rootMetadata.kind == .regular {
            let data = try readEntireRegularFile(at: path, maximumBytes: maximumFileBytes)
            return (1, try body(path, data))
        }
        guard rootMetadata.kind == .directory else {
            throw OmniAgentToolError(
                "Search path '\(path.supplied)' must be a file or directory."
            )
        }

        return try withDirectoryDescriptor(components: path.components[...], create: false) { root in
            var scanned = 0
            var truncated = false
            try searchDirectory(
                descriptor: root,
                path: path,
                maximumFiles: maximumFiles,
                maximumFileBytes: maximumFileBytes,
                scanned: &scanned,
                truncated: &truncated,
                body: body
            )
            return (scanned, truncated)
        }
    }

    private func publishUniqueFile(
        in parent: Int32,
        preferredName: String,
        mode: mode_t,
        path: String,
        writer: (Int32) throws -> Void
    ) throws -> String {
        for attempt in 0..<64 {
            let candidate = attempt == 0 ? preferredName : collisionFileName(preferredName)
            let temporaryName = ".omnibot-host-write-\(UUID().uuidString)"
            let temporary = try openTemporaryFile(
                in: parent,
                name: temporaryName,
                mode: mode,
                path: path
            )
            var didPublish = false
            defer {
                Darwin.close(temporary)
                if !didPublish {
                    temporaryName.withCString { _ = Darwin.unlinkat(parent, $0, 0) }
                }
            }

            try writer(temporary)
            guard Darwin.fsync(temporary) == 0 else {
                throw posixError("fsync host-written file", path: path)
            }
            let renameResult = temporaryName.withCString { temporaryPointer in
                candidate.withCString { candidatePointer in
                    Darwin.renameatx_np(
                        parent,
                        temporaryPointer,
                        parent,
                        candidatePointer,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            if renameResult == 0 {
                didPublish = true
                _ = Darwin.fsync(parent)
                return candidate
            }
            let code = errno
            if code == EEXIST { continue }
            throw posixError("publish unique host-written file", path: path, code: code)
        }
        throw OmniAgentToolError(
            "Could not choose a unique file name beneath '\(path)' after 64 attempts."
        )
    }

    private func collisionFileName(_ preferredName: String) -> String {
        let prefix = "\(UUID().uuidString)-"
        let availableBytes = max(1, Int(NAME_MAX) - prefix.utf8.count)
        return prefix + utf8Prefix(preferredName, maximumBytes: availableBytes)
    }

    private func validatedFileName(_ name: String) throws -> String {
        guard !containsUnsafePathScalars(name) else {
            throw OmniAgentToolError(
                "Workspace file names cannot contain control or bidirectional formatting characters."
            )
        }
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains("\0"),
              name.utf8.count <= Int(NAME_MAX) else {
            throw OmniAgentToolError("Invalid workspace file name: '\(name)'.")
        }
        return name
    }

    private func containsUnsafePathScalars(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            let codePoint = scalar.value
            return codePoint <= 0x1F
                || (0x7F ... 0x9F).contains(codePoint)
                || (0x202A ... 0x202E).contains(codePoint)
                || (0x2066 ... 0x2069).contains(codePoint)
        }
    }

    private func utf8Prefix(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        for character in value {
            let characterBytes = String(character).utf8.count
            guard result.utf8.count <= maximumBytes - characterBytes else { break }
            result.append(character)
        }
        return result.isEmpty ? "file" : result
    }

    private func copyAll(
        from source: Int32,
        to destination: Int32,
        maximumBytes: Int64,
        path: String
    ) throws -> Int64 {
        var copiedBytes: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(source, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count == 0 { return copiedBytes }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError("read source file", path: path)
            }
            let (nextTotal, overflow) = copiedBytes.addingReportingOverflow(Int64(count))
            guard !overflow, nextTotal <= maximumBytes else {
                throw HostWriteLimitError.sourceFileTooLarge(maximumBytes: maximumBytes)
            }
            try buffer.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                try writeAll(
                    UnsafeRawBufferPointer(start: base, count: count),
                    descriptor: destination,
                    path: path
                )
            }
            copiedBytes = nextTotal
        }
    }

    private func copyProjectionSource(
        _ source: DirectoryProjectionSource,
        into staging: Int32,
        maximumFiles: Int,
        maximumBytes: Int64,
        skipsHiddenFiles: Bool,
        copiedFiles: inout Int,
        copiedBytes: inout Int64
    ) throws {
        for component in source.destinationComponents {
            _ = try validatedFileName(component)
        }
        let sourceDescriptor = source.sourceRoot.withUnsafeFileSystemRepresentation {
            pointer -> Int32 in
            guard let pointer else { return -1 }
            return Darwin.open(
                pointer,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard sourceDescriptor >= 0 else {
            throw posixError(
                "open authoritative projection source",
                path: source.sourceRoot.path
            )
        }
        defer { Darwin.close(sourceDescriptor) }

        try withRelativeDirectoryDescriptor(
            from: staging,
            components: source.destinationComponents[...],
            create: true,
            path: source.sourceRoot.path
        ) { destination in
            try copyProjectionDirectory(
                from: sourceDescriptor,
                to: destination,
                sourcePath: source.sourceRoot.path,
                maximumFiles: maximumFiles,
                maximumBytes: maximumBytes,
                skipsHiddenFiles: skipsHiddenFiles,
                copiedFiles: &copiedFiles,
                copiedBytes: &copiedBytes
            )
        }
    }

    private func copyProjectionDirectory(
        from source: Int32,
        to destination: Int32,
        sourcePath: String,
        maximumFiles: Int,
        maximumBytes: Int64,
        skipsHiddenFiles: Bool,
        copiedFiles: inout Int,
        copiedBytes: inout Int64
    ) throws {
        for name in try directoryNames(descriptor: source, maximum: Int.max) {
            if skipsHiddenFiles, name.hasPrefix(".") { continue }
            _ = try validatedFileName(name)
            guard let sourceMetadata = try metadata(
                at: source,
                name: name,
                path: sourcePath
            ) else { continue }

            switch sourceMetadata.kind {
            case .symbolicLink, .other:
                continue
            case .directory:
                let createResult = name.withCString {
                    Darwin.mkdirat(destination, $0, mode_t(0o755))
                }
                guard createResult == 0 || errno == EEXIST else {
                    throw posixError("create projected directory", path: sourcePath)
                }
                let sourceChild = name.withCString {
                    Darwin.openat(
                        source,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                guard sourceChild >= 0 else {
                    throw posixError("open projected source directory", path: sourcePath)
                }
                defer { Darwin.close(sourceChild) }
                let destinationChild = name.withCString {
                    Darwin.openat(
                        destination,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                guard destinationChild >= 0 else {
                    throw posixError("open projected destination directory", path: sourcePath)
                }
                defer { Darwin.close(destinationChild) }
                try copyProjectionDirectory(
                    from: sourceChild,
                    to: destinationChild,
                    sourcePath: sourcePath + "/" + name,
                    maximumFiles: maximumFiles,
                    maximumBytes: maximumBytes,
                    skipsHiddenFiles: skipsHiddenFiles,
                    copiedFiles: &copiedFiles,
                    copiedBytes: &copiedBytes
                )
            case .regular:
                guard copiedFiles < maximumFiles else {
                    throw HostWriteLimitError.projectionFileCountExceeded(maximum: maximumFiles)
                }
                let remainingBytes = maximumBytes - copiedBytes
                guard remainingBytes >= 0, sourceMetadata.size <= remainingBytes else {
                    throw HostWriteLimitError.projectionTotalBytesExceeded(maximum: maximumBytes)
                }
                let sourceFile = name.withCString {
                    Darwin.openat(
                        source,
                        $0,
                        O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
                    )
                }
                guard sourceFile >= 0 else {
                    throw posixError("open projected source file", path: sourcePath + "/" + name)
                }
                defer { Darwin.close(sourceFile) }
                let openedMetadata = try metadata(
                    descriptor: sourceFile,
                    path: sourcePath + "/" + name
                )
                guard openedMetadata.kind == .regular,
                      openedMetadata.size >= 0,
                      openedMetadata.size <= remainingBytes else {
                    throw HostWriteLimitError.projectionTotalBytesExceeded(maximum: maximumBytes)
                }

                let temporaryName = ".omnibot-projection-file-\(UUID().uuidString)"
                let temporary = try openTemporaryFile(
                    in: destination,
                    name: temporaryName,
                    mode: mode_t(openedMetadata.permissions & 0o777),
                    path: sourcePath + "/" + name
                )
                var didPublish = false
                defer {
                    Darwin.close(temporary)
                    if !didPublish {
                        temporaryName.withCString { _ = Darwin.unlinkat(destination, $0, 0) }
                    }
                }
                let actualBytes: Int64
                do {
                    actualBytes = try copyAll(
                        from: sourceFile,
                        to: temporary,
                        maximumBytes: remainingBytes,
                        path: sourcePath + "/" + name
                    )
                } catch is HostWriteLimitError {
                    throw HostWriteLimitError.projectionTotalBytesExceeded(maximum: maximumBytes)
                }
                guard Darwin.fsync(temporary) == 0 else {
                    throw posixError("fsync projected file", path: sourcePath + "/" + name)
                }
                let renameResult = temporaryName.withCString { temporaryPointer in
                    name.withCString { namePointer in
                        Darwin.renameatx_np(
                            destination,
                            temporaryPointer,
                            destination,
                            namePointer,
                            UInt32(RENAME_EXCL)
                        )
                    }
                }
                guard renameResult == 0 else {
                    throw posixError("publish projected file", path: sourcePath + "/" + name)
                }
                didPublish = true
                copiedFiles += 1
                copiedBytes += actualBytes
            }
        }
    }

    private func withRelativeDirectoryDescriptor<T>(
        from root: Int32,
        components: ArraySlice<String>,
        create: Bool,
        path: String,
        body: (Int32) throws -> T
    ) throws -> T {
        var opened: [Int32] = []
        defer { opened.reversed().forEach { Darwin.close($0) } }
        var current = root
        for component in components {
            _ = try validatedFileName(component)
            var next = component.withCString {
                Darwin.openat(
                    current,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            if next < 0, errno == ENOENT, create {
                let mkdirResult = component.withCString {
                    Darwin.mkdirat(current, $0, mode_t(0o755))
                }
                if mkdirResult != 0, errno != EEXIST {
                    throw posixError("create descriptor-relative directory", path: path)
                }
                next = component.withCString {
                    Darwin.openat(
                        current,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
            }
            guard next >= 0 else {
                throw posixError("open descriptor-relative directory", path: path)
            }
            opened.append(next)
            current = next
        }
        return try body(current)
    }

    private func removeEntryRecursively(
        at parent: Int32,
        name: String,
        path: String
    ) throws {
        guard let entry = try metadata(at: parent, name: name, path: path) else { return }
        if entry.kind == .directory {
            let directory = name.withCString {
                Darwin.openat(
                    parent,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard directory >= 0 else {
                throw posixError("open directory for removal", path: path)
            }
            do {
                for child in try directoryNames(descriptor: directory, maximum: Int.max) {
                    try removeEntryRecursively(
                        at: directory,
                        name: child,
                        path: path + "/" + child
                    )
                }
            } catch {
                Darwin.close(directory)
                throw error
            }
            Darwin.close(directory)
            let result = name.withCString { Darwin.unlinkat(parent, $0, AT_REMOVEDIR) }
            if result != 0, errno != ENOENT {
                throw posixError("remove directory", path: path)
            }
            return
        }
        let result = name.withCString { Darwin.unlinkat(parent, $0, 0) }
        if result != 0, errno != ENOENT {
            throw posixError("remove file without following symlinks", path: path)
        }
    }

    private func withRootDescriptor<T>(_ body: (Int32) throws -> T) throws -> T {
        let descriptor = rootURL.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return Darwin.open(
                pointer,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw posixError("open workspace root", path: rootURL.path)
        }
        defer { Darwin.close(descriptor) }
        return try body(descriptor)
    }

    private func withDirectoryDescriptor<T>(
        components: ArraySlice<String>,
        create: Bool,
        body: (Int32) throws -> T
    ) throws -> T {
        try withRootDescriptor { root in
            var opened: [Int32] = []
            defer { opened.reversed().forEach { Darwin.close($0) } }
            var current = root

            for component in components {
                var next = component.withCString {
                    Darwin.openat(
                        current,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                if next < 0, errno == ENOENT, create {
                    let mkdirResult = component.withCString {
                        Darwin.mkdirat(current, $0, mode_t(0o755))
                    }
                    if mkdirResult != 0, errno != EEXIST {
                        throw posixError("create directory", path: component)
                    }
                    next = component.withCString {
                        Darwin.openat(
                            current,
                            $0,
                            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                        )
                    }
                }
                guard next >= 0 else {
                    throw posixError("open directory without following symlinks", path: component)
                }
                opened.append(next)
                current = next
            }
            return try body(current)
        }
    }

    private func metadata(
        at parent: Int32,
        name: String,
        path: String
    ) throws -> ItemMetadata? {
        var status = stat()
        let result = name.withCString {
            Darwin.fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            return makeMetadata(status)
        }
        if errno == ENOENT {
            return nil
        }
        throw posixError("inspect", path: path)
    }

    private func metadata(descriptor: Int32, path: String) throws -> ItemMetadata {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw posixError("inspect open file", path: path)
        }
        return makeMetadata(status)
    }

    private func makeMetadata(_ status: stat) -> ItemMetadata {
        let kind: ItemKind
        switch status.st_mode & S_IFMT {
        case S_IFREG: kind = .regular
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }
        return ItemMetadata(
            kind: kind,
            size: status.st_size,
            permissions: status.st_mode & 0o7777,
            device: status.st_dev,
            inode: status.st_ino,
            modifiedAt: date(status.st_mtimespec),
            createdAt: date(status.st_birthtimespec)
        )
    }

    private func openRegularFile(at parent: Int32, name: String, path: String) throws -> Int32 {
        let descriptor = name.withCString {
            Darwin.openat(
                parent,
                $0,
                O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw posixError("open regular file without following symlinks", path: path)
        }
        do {
            let metadata = try metadata(descriptor: descriptor, path: path)
            guard metadata.kind == .regular else {
                throw OmniAgentToolError("Path '\(path)' is not a regular file.")
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func openTemporaryFile(
        in parent: Int32,
        name: String,
        mode: mode_t,
        path: String
    ) throws -> Int32 {
        let descriptor = name.withCString {
            Darwin.openat(
                parent,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode
            )
        }
        guard descriptor >= 0 else {
            throw posixError("create temporary file", path: path)
        }
        return descriptor
    }

    private func preadData(
        descriptor: Int32,
        offset: Int,
        count: Int,
        path: String
    ) throws -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        var total = 0
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            while total < count {
                let readCount = Darwin.pread(
                    descriptor,
                    base.advanced(by: total),
                    count - total,
                    off_t(offset + total)
                )
                if readCount == 0 { break }
                if readCount < 0 {
                    if errno == EINTR { continue }
                    throw posixError("read", path: path)
                }
                total += readCount
            }
        }
        if total < count {
            data.removeSubrange(total..<data.count)
        }
        return data
    }

    private func writeAll(_ data: Data, descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { rawBuffer in
            try writeAll(rawBuffer, descriptor: descriptor, path: path)
        }
    }

    private func writeAll(
        _ rawBuffer: UnsafeRawBufferPointer,
        descriptor: Int32,
        path: String
    ) throws {
        guard let base = rawBuffer.baseAddress else { return }
        var total = 0
        while total < rawBuffer.count {
            let written = Darwin.write(
                descriptor,
                base.advanced(by: total),
                rawBuffer.count - total
            )
            if written < 0 {
                if errno == EINTR { continue }
                throw posixError("write", path: path)
            }
            guard written > 0 else {
                throw OmniAgentToolError("Writing '\(path)' made no progress.")
            }
            total += written
        }
    }

    private func enumerateDirectory(
        descriptor: Int32,
        path: RelativePath,
        recursive: Bool,
        maximumEntries: Int,
        entries: inout [DirectoryEntry],
        truncated: inout Bool
    ) throws {
        let names = try directoryNames(descriptor: descriptor, maximum: maximumEntries + 1)
        for name in names {
            if entries.count >= maximumEntries {
                truncated = true
                return
            }
            guard let metadata = try metadata(at: descriptor, name: name, path: path.displayPath) else {
                continue
            }
            let childPath = path.appending(name)
            entries.append(DirectoryEntry(path: childPath, metadata: metadata))

            if recursive, metadata.kind == .directory {
                let child = name.withCString {
                    Darwin.openat(
                        descriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                if child >= 0 {
                    defer { Darwin.close(child) }
                    try enumerateDirectory(
                        descriptor: child,
                        path: childPath,
                        recursive: true,
                        maximumEntries: maximumEntries,
                        entries: &entries,
                        truncated: &truncated
                    )
                    if truncated { return }
                }
            }
        }
        if names.count > maximumEntries {
            truncated = true
        }
    }

    private func searchDirectory(
        descriptor: Int32,
        path: RelativePath,
        maximumFiles: Int,
        maximumFileBytes: Int,
        scanned: inout Int,
        truncated: inout Bool,
        body: (RelativePath, Data) throws -> Bool
    ) throws {
        let names = try directoryNames(descriptor: descriptor, maximum: maximumFiles + 1)
        for name in names {
            if scanned >= maximumFiles {
                truncated = true
                return
            }
            guard let metadata = try metadata(at: descriptor, name: name, path: path.displayPath) else {
                continue
            }
            let childPath = path.appending(name)
            switch metadata.kind {
            case .regular:
                guard metadata.size >= 0, metadata.size <= Int64(maximumFileBytes) else { continue }
                let file = name.withCString {
                    Darwin.openat(
                        descriptor,
                        $0,
                        O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
                    )
                }
                guard file >= 0 else { continue }
                defer { Darwin.close(file) }
                guard let openedMetadata = try? self.metadata(
                    descriptor: file,
                    path: childPath.displayPath
                ), openedMetadata.kind == .regular,
                    openedMetadata.size >= 0,
                    openedMetadata.size <= Int64(maximumFileBytes) else {
                    continue
                }
                let data = try preadData(
                    descriptor: file,
                    offset: 0,
                    count: Int(openedMetadata.size),
                    path: childPath.displayPath
                )
                scanned += 1
                if try body(childPath, data) {
                    truncated = true
                    return
                }
            case .directory:
                let child = name.withCString {
                    Darwin.openat(
                        descriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                guard child >= 0 else { continue }
                defer { Darwin.close(child) }
                try searchDirectory(
                    descriptor: child,
                    path: childPath,
                    maximumFiles: maximumFiles,
                    maximumFileBytes: maximumFileBytes,
                    scanned: &scanned,
                    truncated: &truncated,
                    body: body
                )
                if truncated { return }
            case .symbolicLink, .other:
                continue
            }
        }
        if names.count > maximumFiles {
            truncated = true
        }
    }

    private func directoryNames(descriptor: Int32, maximum: Int) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else {
            throw posixError("duplicate directory descriptor", path: rootURL.path)
        }
        guard let directory = Darwin.fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw posixError("enumerate directory", path: rootURL.path)
        }
        defer { Darwin.closedir(directory) }

        var names: [String] = []
        while let entry = Darwin.readdir(directory) {
            let nameLength = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: UInt8.self, capacity: nameLength) {
                    String(decoding: UnsafeBufferPointer(start: $0, count: nameLength), as: UTF8.self)
                }
            }
            guard name != ".", name != ".." else { continue }
            names.append(name)
            if names.count >= maximum { break }
        }
        return names.sorted()
    }

    private func componentsOverlap(_ first: [String], _ second: [String]) -> Bool {
        first.starts(with: second) || second.starts(with: first)
    }

    private func date(_ value: timespec) -> Date {
        Date(
            timeIntervalSince1970: TimeInterval(value.tv_sec)
                + TimeInterval(value.tv_nsec) / 1_000_000_000
        )
    }

    private func posixError(
        _ operation: String,
        path: String,
        code: Int32 = errno
    ) -> OmniAgentToolError {
        let message = String(cString: strerror(code))
        return OmniAgentToolError("Could not \(operation) '\(path)': \(message) (errno \(code)).")
    }
}
