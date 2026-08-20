import Darwin
import Foundation

nonisolated public struct WorkspacePaths: Hashable, Sendable {
    public let root: URL
    public let controlRoot: URL

    /// Host-only state. This directory is deliberately outside `root`, because
    /// `root` is writable by both the model tools and the Alpine guest.
    public var hostOmniBotDirectory: URL {
        controlRoot.appending(path: ".omnibot", directoryHint: .isDirectory)
    }
    public var agentDirectory: URL {
        hostOmniBotDirectory.appending(path: "agent", directoryHint: .isDirectory)
    }
    public var memoryDirectory: URL {
        hostOmniBotDirectory.appending(path: "memory", directoryHint: .isDirectory)
    }
    /// Host-authoritative skill packages. The Alpine guest and model tools do
    /// not mount this directory, so workspace writes cannot become persistent
    /// system-prompt instructions on a later turn.
    public var authoritativeSkillsDirectory: URL {
        hostOmniBotDirectory.appending(path: "skills", directoryHint: .isDirectory)
    }
    /// Host-only snapshots handed to Quick Look. Workspace and Alpine guest
    /// writes cannot alter a preview after its source descriptor is copied.
    public var previewCacheDirectory: URL {
        hostOmniBotDirectory.appending(path: "PreviewCache", directoryHint: .isDirectory)
    }
    public var skillRegistryFile: URL {
        authoritativeSkillsDirectory.appending(path: ".registry.json")
    }
    public var shortMemoryDirectory: URL {
        memoryDirectory.appending(path: "short-memories", directoryHint: .isDirectory)
    }

    /// Model-visible Agent resources. These paths intentionally live inside the
    /// shared workspace, unlike credentials, provider configuration, SOUL, and
    /// memory control files above.
    public var workspaceOmniBotDirectory: URL {
        root.appending(path: ".omnibot", directoryHint: .isDirectory)
    }
    public var attachmentsDirectory: URL {
        workspaceOmniBotDirectory.appending(path: "attachments", directoryHint: .isDirectory)
    }
    public var sharedDirectory: URL {
        workspaceOmniBotDirectory.appending(path: "shared", directoryHint: .isDirectory)
    }
    public var offloadsDirectory: URL {
        workspaceOmniBotDirectory.appending(path: "offloads", directoryHint: .isDirectory)
    }
    public var browserDirectory: URL {
        workspaceOmniBotDirectory.appending(path: "browser", directoryHint: .isDirectory)
    }
    /// A disposable, model-visible projection of explicitly enabled skills.
    /// AgentSkillStore always reads authoritative content from
    /// `authoritativeSkillsDirectory`, never from this directory.
    public var skillsDirectory: URL {
        workspaceOmniBotDirectory.appending(path: "skills", directoryHint: .isDirectory)
    }

    public var soulFile: URL { agentDirectory.appending(path: "SOUL.md") }
    public var providerConfigFile: URL { agentDirectory.appending(path: "providers.json") }
    public var agentConfigFile: URL { agentDirectory.appending(path: "config.json") }
    public var longTermMemoryFile: URL { memoryDirectory.appending(path: "MEMORY.md") }
    public var harnessFailuresFile: URL {
        memoryDirectory.appending(path: "HARNESS_ERRORS.md")
    }
    public var memoryIndexFile: URL { memoryDirectory.appending(path: "index.json") }

    public init(root: URL, controlRoot: URL) {
        self.root = root.standardizedFileURL
        self.controlRoot = controlRoot.standardizedFileURL
    }

    public static func applicationSupport(
        appName: String = "OmniBot",
        fileManager: FileManager = .default
    ) throws -> WorkspacePaths {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw WorkspacePathError.unavailableApplicationSupport
        }
        let appDirectory = base.appending(path: appName, directoryHint: .isDirectory)
        return WorkspacePaths(
            root: appDirectory.appending(path: "workspace", directoryHint: .isDirectory),
            controlRoot: appDirectory.appending(path: "Control", directoryHint: .isDirectory)
        )
    }

    public func prepare(fileManager: FileManager = .default) throws {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let canonicalControlRoot = controlRoot.resolvingSymlinksInPath().standardizedFileURL
        guard !canonicalControlRoot.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw WorkspacePathError.controlDirectoryInsideWorkspace
        }

        // Both parents live in host-owned Application Support. Reject a replaced
        // leaf before the one unavoidable absolute creation of each root; all
        // descendants of the shared workspace are created descriptor-relative.
        try rejectSymbolicLink(root)
        try rejectSymbolicLink(controlRoot)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: controlRoot, withIntermediateDirectories: true)

        // Quarantine the pre-isolation layout instead of activating it. It was
        // writable by the guest, so even an HTTPS provider URL in that folder
        // cannot be trusted with a Keychain credential after an upgrade.
        let isolationMarker = controlRoot.appending(path: ".workspace-isolation-v2")
        if !fileManager.fileExists(atPath: isolationMarker.path) {
            try quarantineLegacyWorkspaceControl(fileManager: fileManager)
            try Data("host-control-isolated\n".utf8).write(to: isolationMarker, options: .atomic)
        }

        let workspaceFileSystem = WorkspaceDescriptorFileSystem(paths: self)
        try createWorkspaceDirectory(
            ".omnibot",
            workspaceFileSystem: workspaceFileSystem
        )

        try migrateLegacySharedDirectory(
            named: "attachments",
            to: attachmentsDirectory,
            workspaceFileSystem: workspaceFileSystem,
            fileManager: fileManager
        )
        try migrateLegacySharedDirectory(
            named: "shared",
            to: sharedDirectory,
            workspaceFileSystem: workspaceFileSystem,
            fileManager: fileManager
        )
        try migrateLegacySharedDirectory(
            named: "offloads",
            to: offloadsDirectory,
            workspaceFileSystem: workspaceFileSystem,
            fileManager: fileManager
        )

        for directory in [
            controlRoot,
            hostOmniBotDirectory,
            agentDirectory,
            memoryDirectory,
            authoritativeSkillsDirectory,
            shortMemoryDirectory,
            previewCacheDirectory,
        ] {
            try createManagedDirectory(
                directory,
                base: controlRoot,
                fileManager: fileManager
            )
        }
        for relativePath in [
            ".omnibot/attachments",
            ".omnibot/shared",
            ".omnibot/offloads",
            ".omnibot/browser",
            ".omnibot/skills",
        ] {
            try createWorkspaceDirectory(
                relativePath,
                workspaceFileSystem: workspaceFileSystem
            )
        }
    }

    /// Resolves a user or tool supplied relative path without allowing workspace escape.
    public func resolve(relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw WorkspacePathError.absolutePathNotAllowed(relativePath)
        }

        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root
            .appending(path: relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        let rootComponents = canonicalRoot.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.starts(with: rootComponents) else {
            throw WorkspacePathError.pathEscapesRoot(relativePath)
        }
        return candidate
    }

    private func migrateLegacySharedDirectory(
        named name: String,
        to destination: URL,
        workspaceFileSystem: WorkspaceDescriptorFileSystem,
        fileManager: FileManager
    ) throws {
        let source = root.appending(path: name, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: source.path),
              !fileManager.fileExists(atPath: destination.path) else {
            return
        }
        let sourcePath = try workspaceFileSystem.parse(name)
        let destinationPath = try workspaceFileSystem.parse(".omnibot/\(name)")
        do {
            _ = try workspaceFileSystem.move(
                from: sourcePath,
                to: destinationPath,
                overwrite: false
            )
        } catch {
            if (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw WorkspacePathError.managedPathIsSymbolicLink(source.path)
            }
            throw error
        }
    }

    private func quarantineLegacyWorkspaceControl(
        fileManager: FileManager
    ) throws {
        let quarantineDirectory = controlRoot
            .appending(path: "Quarantine", directoryHint: .isDirectory)
        try createManagedDirectory(
            quarantineDirectory,
            base: controlRoot,
            fileManager: fileManager
        )

        let workspaceDescriptor = root.withUnsafeFileSystemRepresentation {
            pointer -> Int32 in
            guard let pointer else { return -1 }
            return Darwin.open(
                pointer,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard workspaceDescriptor >= 0 else {
            throw WorkspacePathError.managedPathIsSymbolicLink(root.path)
        }
        defer { Darwin.close(workspaceDescriptor) }

        let quarantineDescriptor = quarantineDirectory.withUnsafeFileSystemRepresentation {
            pointer -> Int32 in
            guard let pointer else { return -1 }
            return Darwin.open(
                pointer,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard quarantineDescriptor >= 0 else {
            throw WorkspacePathError.managedPathIsSymbolicLink(quarantineDirectory.path)
        }
        defer { Darwin.close(quarantineDescriptor) }

        let destinationName = "legacy-workspace-control-\(UUID().uuidString)"
        let result = ".omnibot".withCString { sourcePointer in
            destinationName.withCString { destinationPointer in
                Darwin.renameatx_np(
                    workspaceDescriptor,
                    sourcePointer,
                    quarantineDescriptor,
                    destinationPointer,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        if result != 0, errno != ENOENT {
            let code = errno
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [
                    NSFilePathErrorKey: root.appending(path: ".omnibot").path,
                    NSLocalizedDescriptionKey: "Could not quarantine the legacy workspace control directory (errno \(code)).",
                ]
            )
        }
    }

    private func createManagedDirectory(
        _ directory: URL,
        base: URL,
        fileManager: FileManager
    ) throws {
        let standardizedBase = base.standardizedFileURL
        let standardizedDirectory = directory.standardizedFileURL
        guard standardizedDirectory.pathComponents.starts(with: standardizedBase.pathComponents) else {
            throw WorkspacePathError.pathEscapesRoot(directory.path)
        }

        var candidate = standardizedBase
        try rejectSymbolicLink(candidate)
        for component in standardizedDirectory.pathComponents.dropFirst(
            standardizedBase.pathComponents.count
        ) {
            candidate = candidate.appending(path: component)
            try rejectSymbolicLink(candidate)
        }
        try fileManager.createDirectory(
            at: standardizedDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Keeps the public `WorkspacePaths.prepare()` error contract while the
    /// descriptor filesystem remains the source of truth for the operation.
    /// This inspection only classifies an already-failed write; it is never
    /// used to authorize or perform the workspace mutation.
    private func createWorkspaceDirectory(
        _ relativePath: String,
        workspaceFileSystem: WorkspaceDescriptorFileSystem
    ) throws {
        do {
            try workspaceFileSystem.createDirectory(
                workspaceFileSystem.parse(relativePath)
            )
        } catch {
            var candidate = root
            for component in relativePath.split(separator: "/") {
                candidate.append(path: String(component), directoryHint: .isDirectory)
                if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw WorkspacePathError.managedPathIsSymbolicLink(candidate.path)
                }
            }
            throw error
        }
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
              values.isSymbolicLink == true else {
            return
        }
        throw WorkspacePathError.managedPathIsSymbolicLink(url.path)
    }
}
