import Darwin
import Foundation
import UniformTypeIdentifiers

nonisolated public struct AgentResourceProtocol: Sendable {
    public static let scheme = "omnibot"
    public static let maximumQuickLookPreviewBytes: Int64 = 256 * 1_024 * 1_024
    static let maximumQuickLookCacheFiles = 32
    static let maximumQuickLookCacheBytes: Int64 = 512 * 1_024 * 1_024

    private static let quickLookCacheMaximumAge: TimeInterval = 24 * 60 * 60
    private static let quickLookCacheLock = NSLock()

    private struct PreviewCacheUsage {
        let fileCount: Int
        let totalBytes: Int64
    }

    private let paths: WorkspacePaths
    private let workspaceFileSystem: WorkspaceDescriptorFileSystem

    public init(paths: WorkspacePaths) {
        self.paths = paths
        workspaceFileSystem = WorkspaceDescriptorFileSystem(paths: paths)
    }

    public func artifact(
        for fileURL: URL,
        sourceTool: String,
        title: String? = nil
    ) throws -> AgentArtifact {
        // The URL is used only as a lexical workspace-relative identifier.
        // Metadata is read through a pinned descriptor walk, so a workspace
        // symlink swap cannot redirect artifact construction outside root.
        let path = try descriptorRelativePath(forWorkspaceURL: fileURL)
        let metadata = try workspaceFileSystem.metadata(for: path)
        guard metadata.kind == .regular else {
            throw AgentResourceError.notRegularFile(path.displayPath)
        }

        let workspaceURL = workspaceURL(for: path)
        let uri = try resourceURI(for: path)
        let mimeType = Self.mimeType(for: workspaceURL)
        let previewKind = Self.previewKind(mimeType: mimeType, fileURL: workspaceURL)
        let displayTitle = title.map(Self.normalizedTitle)
        let resolvedTitle = if let displayTitle, !displayTitle.isEmpty {
            displayTitle
        } else {
            Self.normalizedTitle(workspaceURL.lastPathComponent)
        }
        let actions = [
            AgentArtifactAction(type: "preview", label: "Preview", target: uri),
            AgentArtifactAction(type: "save", label: "Save", target: uri),
        ]
        return AgentArtifact(
            id: uri,
            uri: uri,
            title: resolvedTitle,
            fileName: workspaceURL.lastPathComponent,
            mimeType: mimeType,
            size: metadata.size,
            sourceTool: sourceTool,
            workspacePath: path.displayPath,
            hostPath: workspaceURL.path,
            previewKind: previewKind,
            actions: actions
        )
    }

    public func resourceURI(for fileURL: URL) throws -> String {
        try resourceURI(for: descriptorRelativePath(forWorkspaceURL: fileURL))
    }

    /// Returns a lexical workspace URL for compatibility with callers that
    /// only need to identify the resource. Code that reads resource bytes must
    /// use `readData` or `makeQuickLookSnapshot` instead of reopening this URL.
    public func resolve(_ resourceURL: URL) throws -> URL {
        let path = try descriptorRelativePath(for: resourceURL)
        let metadata: WorkspaceDescriptorFileSystem.ItemMetadata
        do {
            metadata = try workspaceFileSystem.metadata(for: path)
        } catch {
            throw AgentResourceError.missingFile(resourceURL.absoluteString)
        }
        guard metadata.kind != .symbolicLink else {
            throw AgentResourceError.pathOutsideAuthority(resourceURL.absoluteString)
        }
        return workspaceURL(for: path)
    }

    /// Reads an omnibot resource through one descriptor-pinned, no-follow file
    /// handle and enforces the byte limit against that same opened file.
    public func readData(
        _ resourceURL: URL,
        maximumBytes: Int
    ) throws -> Data {
        guard maximumBytes >= 0 else {
            throw AgentResourceError.invalidResourceURL(resourceURL.absoluteString)
        }
        let path = try descriptorRelativePath(for: resourceURL)
        let metadata = try workspaceFileSystem.metadata(for: path)
        guard metadata.kind == .regular else {
            if metadata.kind == .symbolicLink {
                throw AgentResourceError.pathOutsideAuthority(resourceURL.absoluteString)
            }
            throw AgentResourceError.notRegularFile(path.displayPath)
        }
        return try workspaceFileSystem.readEntireRegularFile(
            at: path,
            maximumBytes: maximumBytes
        )
    }

    /// Materializes a stable, host-only Quick Look snapshot. The workspace
    /// source is opened with descriptor-relative O_NOFOLLOW traversal and then
    /// streamed with a hard byte bound into Control/PreviewCache.
    public func makeQuickLookSnapshot(
        for resourceURL: URL,
        maximumBytes: Int64 = AgentResourceProtocol.maximumQuickLookPreviewBytes
    ) throws -> URL {
        guard maximumBytes >= 0 else {
            throw AgentResourceError.invalidResourceURL(resourceURL.absoluteString)
        }
        let path = try descriptorRelativePath(for: resourceURL)
        return try Self.quickLookCacheLock.withLock {
            try preparePreviewCache()
            let usage = try maintainPreviewCache()
            guard usage.fileCount < Self.maximumQuickLookCacheFiles,
                  usage.totalBytes <= Self.maximumQuickLookCacheBytes else {
                throw AgentResourceError.previewCacheLimitExceeded
            }
            let availableBytes = Self.maximumQuickLookCacheBytes - usage.totalBytes
            let boundedMaximum = min(maximumBytes, availableBytes)
            return try workspaceFileSystem.copyRegularFileToHostSnapshot(
                at: path,
                destinationDirectory: paths.previewCacheDirectory,
                preferredName: path.leafName ?? "Preview",
                maximumBytes: boundedMaximum
            )
        }
    }

    /// Removes only a direct child previously created in PreviewCache. Cleanup
    /// is descriptor-relative too, so even host-side replacement of the leaf
    /// cannot turn cleanup into an arbitrary-path deletion.
    public func removeQuickLookSnapshot(_ snapshotURL: URL) {
        Self.quickLookCacheLock.withLock {
            _ = unlinkQuickLookSnapshot(snapshotURL)
        }
    }

    private func unlinkQuickLookSnapshot(_ snapshotURL: URL) -> Bool {
        let cache = paths.previewCacheDirectory.standardizedFileURL
        let snapshot = snapshotURL.standardizedFileURL
        guard snapshot.isFileURL,
              snapshot.deletingLastPathComponent().path == cache.path,
              !snapshot.lastPathComponent.isEmpty,
              snapshot.lastPathComponent != ".",
              snapshot.lastPathComponent != "..",
              !snapshot.lastPathComponent.contains("/"),
              !snapshot.lastPathComponent.contains("\\") else {
            return false
        }

        let directory = cache.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return Darwin.open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard directory >= 0 else { return false }
        defer { Darwin.close(directory) }
        let result = snapshot.lastPathComponent.withCString {
            Darwin.unlinkat(directory, $0, 0)
        }
        return result == 0 || errno == ENOENT
    }

    public func shellPath(for fileURL: URL) throws -> String {
        try descriptorRelativePath(forWorkspaceURL: fileURL).displayPath
    }

    /// Maps an omnibot URI directly to a descriptor-relative workspace path.
    /// No canonical absolute URL is created or checked as an authorization
    /// decision, eliminating validate-then-reopen races.
    func descriptorRelativePath(
        for resourceURL: URL
    ) throws -> WorkspaceDescriptorFileSystem.RelativePath {
        guard let urlComponents = URLComponents(
            url: resourceURL,
            resolvingAgainstBaseURL: false
        ),
              urlComponents.scheme?.lowercased() == Self.scheme,
              let authority = urlComponents.host?.lowercased(),
              !authority.isEmpty else {
            throw AgentResourceError.unsupportedResourceURL(resourceURL.absoluteString)
        }
        guard urlComponents.user == nil,
              urlComponents.password == nil,
              urlComponents.port == nil,
              urlComponents.query == nil,
              urlComponents.fragment == nil,
              urlComponents.percentEncodedHost?.contains("%") != true else {
            throw AgentResourceError.invalidResourceURL(resourceURL.absoluteString)
        }

        let prefix: [String]
        switch authority {
        case "workspace": prefix = []
        case "attachments": prefix = [".omnibot", "attachments"]
        case "shared": prefix = [".omnibot", "shared"]
        case "offloads": prefix = [".omnibot", "offloads"]
        case "browser": prefix = [".omnibot", "browser"]
        case "skills": prefix = [".omnibot", "skills"]
        default:
            throw AgentResourceError.unsupportedAuthority(authority)
        }

        let resourceComponents = try decodedPathComponents(
            urlComponents.percentEncodedPath,
            originalURL: resourceURL.absoluteString
        )
        let components = prefix + resourceComponents
        do {
            return try workspaceFileSystem.parse(
                components.isEmpty ? "." : components.joined(separator: "/")
            )
        } catch {
            throw AgentResourceError.invalidResourceURL(resourceURL.absoluteString)
        }
    }

    private func descriptorRelativePath(
        forWorkspaceURL fileURL: URL
    ) throws -> WorkspaceDescriptorFileSystem.RelativePath {
        guard fileURL.isFileURL else {
            throw AgentResourceError.invalidResourceURL(fileURL.absoluteString)
        }
        let root = paths.root.standardizedFileURL
        let candidate = fileURL.standardizedFileURL
        guard candidate.pathComponents.starts(with: root.pathComponents) else {
            throw AgentResourceError.pathOutsideWorkspace(candidate.path)
        }
        let components = Array(
            candidate.pathComponents.dropFirst(root.pathComponents.count)
        )
        do {
            return try workspaceFileSystem.parse(
                components.isEmpty ? "." : components.joined(separator: "/")
            )
        } catch {
            throw AgentResourceError.invalidResourceURL(fileURL.absoluteString)
        }
    }

    private func resourceURI(
        for path: WorkspaceDescriptorFileSystem.RelativePath
    ) throws -> String {
        let mapping = authorityAndPath(for: path.components)
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = mapping.authority
        components.path = mapping.components.isEmpty
            ? ""
            : "/" + mapping.components.joined(separator: "/")
        guard let value = components.url?.absoluteString else {
            throw AgentResourceError.invalidResourceURL(path.displayPath)
        }
        return value
    }

    private func authorityAndPath(
        for relative: [String]
    ) -> (authority: String, components: [String]) {
        guard relative.count >= 2, relative[0] == ".omnibot" else {
            return ("workspace", relative)
        }
        switch relative[1] {
        case "attachments", "shared", "offloads", "browser", "skills":
            return (relative[1], Array(relative.dropFirst(2)))
        default:
            return ("workspace", relative)
        }
    }

    private func decodedPathComponents(
        _ percentEncodedPath: String,
        originalURL: String
    ) throws -> [String] {
        guard percentEncodedPath.isEmpty || percentEncodedPath.hasPrefix("/") else {
            throw AgentResourceError.invalidResourceURL(originalURL)
        }
        if percentEncodedPath.isEmpty || percentEncodedPath == "/" { return [] }
        let encodedComponents = percentEncodedPath
            .dropFirst()
            .split(separator: "/", omittingEmptySubsequences: false)
        return try encodedComponents.map { encodedComponent in
            guard !encodedComponent.isEmpty,
                  let decoded = String(encodedComponent).removingPercentEncoding,
                  !decoded.isEmpty,
                  decoded != ".",
                  decoded != "..",
                  !decoded.contains("/"),
                  !decoded.contains("\\"),
                  !decoded.contains("\0") else {
                throw AgentResourceError.invalidResourceURL(originalURL)
            }
            return decoded
        }
    }

    private func workspaceURL(
        for path: WorkspaceDescriptorFileSystem.RelativePath
    ) -> URL {
        path.components.reduce(paths.root) { partial, component in
            partial.appending(path: component)
        }
        .standardizedFileURL
    }

    private func preparePreviewCache() throws {
        let directory = paths.previewCacheDirectory
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw AgentResourceError.previewCacheUnavailable
        }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw AgentResourceError.previewCacheUnavailable
        }
        guard (try? directory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true else {
            throw AgentResourceError.previewCacheUnavailable
        }
    }

    /// Deletes only direct regular files older than 24 hours. Recent files may
    /// still be in use by Quick Look and are counted against a hard cache quota
    /// instead of being evicted underneath an active preview.
    private func maintainPreviewCache(now: Date = .now) throws -> PreviewCacheUsage {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: paths.previewCacheDirectory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            )
        } catch {
            throw AgentResourceError.previewCacheUnavailable
        }

        let staleBefore = now.addingTimeInterval(-Self.quickLookCacheMaximumAge)
        var fileCount = 0
        var totalBytes: Int64 = 0
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            if let modifiedAt = values.contentModificationDate,
               modifiedAt < staleBefore,
               unlinkQuickLookSnapshot(entry) {
                continue
            }

            fileCount += 1
            let fileBytes = Int64(max(0, values.fileSize ?? 0))
            let (nextTotal, overflow) = totalBytes.addingReportingOverflow(fileBytes)
            totalBytes = overflow ? Int64.max : nextTotal
        }
        return PreviewCacheUsage(fileCount: fileCount, totalBytes: totalBytes)
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "docm": return "application/vnd.ms-word.document.macroEnabled.12"
        case "xlsm": return "application/vnd.ms-excel.sheet.macroEnabled.12"
        case "pptm": return "application/vnd.ms-powerpoint.presentation.macroEnabled.12"
        case "jsonl", "ndjson": return "application/x-ndjson"
        case "yaml", "yml": return "application/yaml"
        default: break
        }
        return UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    private static func normalizedTitle(_ value: String) -> String {
        let collapsed = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(256))
    }

    private static func previewKind(mimeType: String, fileURL: URL) -> String {
        if mimeType.hasPrefix("image/") { return "image" }
        if mimeType.hasPrefix("audio/") { return "audio" }
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType == "application/pdf" { return "pdf" }
        if mimeType == "text/html" { return "html" }
        if [
            "application/json",
            "application/xml",
            "application/yaml",
            "application/x-yaml",
            "application/x-ndjson",
            "text/xml",
            "text/yaml",
        ].contains(mimeType)
            || mimeType.hasSuffix("+json")
            || mimeType.hasSuffix("+xml") {
            return "code"
        }
        switch fileURL.pathExtension.lowercased() {
        case "doc", "docx", "docm", "pages": return "office_word"
        case "xls", "xlsx", "xlsm", "numbers": return "office_sheet"
        case "ppt", "pptx", "pptm", "key": return "office_slide"
        case "json", "jsonl", "xml", "yaml", "yml", "ndjson": return "code"
        case "md", "txt", "csv", "log": return "text"
        default: return "file"
        }
    }
}

nonisolated public enum AgentResourceError: LocalizedError, Sendable {
    case invalidResourceURL(String)
    case unsupportedResourceURL(String)
    case unsupportedAuthority(String)
    case pathOutsideWorkspace(String)
    case pathOutsideAuthority(String)
    case missingFile(String)
    case notRegularFile(String)
    case previewCacheUnavailable
    case previewCacheLimitExceeded

    public var errorDescription: String? {
        switch self {
        case let .invalidResourceURL(value): "Invalid Omnibot resource URL: \(value)"
        case let .unsupportedResourceURL(value): "Unsupported Omnibot resource URL: \(value)"
        case let .unsupportedAuthority(value): "Unsupported Omnibot resource authority: \(value)"
        case let .pathOutsideWorkspace(value): "Resource path is outside the workspace: \(value)"
        case let .pathOutsideAuthority(value): "Resource path escapes its Omnibot authority: \(value)"
        case let .missingFile(value): "Resource file does not exist: \(value)"
        case let .notRegularFile(value): "Resource is not a regular file: \(value)"
        case .previewCacheUnavailable: "The secure Quick Look preview cache is unavailable."
        case .previewCacheLimitExceeded: "The secure Quick Look preview cache is full. Close previews or try again later."
        }
    }
}
