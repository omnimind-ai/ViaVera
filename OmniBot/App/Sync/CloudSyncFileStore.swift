import CryptoKit
import Foundation

nonisolated enum CloudSyncCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

/// All workspace I/O uses the existing descriptor-relative, no-symlink
/// filesystem boundary. Sync does not weaken host/guest isolation.
actor CloudSyncFileStore {
    private struct CachedFile {
        let size: Int64
        let modifiedAt: Date
        let inode: UInt64
        let device: Int32
        let digest: String
    }
    private let paths: WorkspacePaths
    private let cache: URL
    private let keychain: any APIKeyStoring
    private let cacheKeyID = "cache-encryption-v1"
    private let controlFiles: WorkspaceDescriptorFileSystem
    private let workspaceFiles: WorkspaceDescriptorFileSystem
    private var inventoryCache: [String: CachedFile] = [:]

    init(paths: WorkspacePaths, keychain: any APIKeyStoring = KeychainAPIKeyStore(
        service: "\(Bundle.main.bundleIdentifier ?? "OmniBot").cloud-sync-cache")) {
        self.paths = paths
        self.keychain = keychain
        cache = paths.controlRoot.appending(path: "CloudSync", directoryHint: .isDirectory)
        controlFiles = WorkspaceDescriptorFileSystem(paths: WorkspacePaths(root: paths.hostOmniBotDirectory, controlRoot: paths.controlRoot))
        workspaceFiles = WorkspaceDescriptorFileSystem(paths: paths)
    }

    func loadIndex() throws -> CloudSyncIndex {
        try prepareCache()
        let url = cache.appending(path: "index.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return CloudSyncIndex() }
        let value = try JSONDecoder().decode(CloudSyncIndex.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw CloudSyncError.invalidData }
        return value
    }

    func saveIndex(_ index: CloudSyncIndex) throws {
        try prepareCache()
        try CloudSyncCoding.encode(index).write(to: cache.appending(path: "index.json"), options: .atomic)
    }

    func archiveIndex(_ index: CloudSyncIndex) throws {
        try prepareCache()
        try CloudSyncCoding.encode(index).write(to: cache.appending(path: "previous-account-\(UUID().uuidString).json"), options: .atomic)
    }

    func cachePayload(_ data: Data, sensitive: Bool = false) throws -> String {
        guard data.count <= CloudSyncScope.maximumDocumentBytes else { throw CloudSyncError.dataTooLarge }
        try prepareCache()
        let digest = CloudSyncRevision.hash(data)
        if sensitive {
            let url = cache.appending(path: "objects/\(digest).sealed")
            if !FileManager.default.fileExists(atPath: url.path) {
                let sealed = try AES.GCM.seal(data, using: encryptionKey(create: true), authenticating: Data(digest.utf8))
                guard let combined = sealed.combined else { throw CloudSyncError.invalidData }
                try combined.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            // Upgrade old metadata-only objects without leaving a second copy.
            let plain = cache.appending(path: "objects/\(digest)")
            if FileManager.default.fileExists(atPath: plain.path) { try FileManager.default.removeItem(at: plain) }
            return digest
        }
        let url = cache.appending(path: "objects/\(digest)")
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return digest
    }

    func payload(_ digest: String) throws -> Data {
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { throw CloudSyncError.invalidData }
        let sealed = cache.appending(path: "objects/\(digest).sealed")
        let data: Data
        if FileManager.default.fileExists(atPath: sealed.path) {
            data = try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: sealed)),
                                    using: encryptionKey(create: false), authenticating: Data(digest.utf8))
        } else {
            data = try Data(contentsOf: cache.appending(path: "objects/\(digest)"))
        }
        guard data.count <= CloudSyncScope.maximumDocumentBytes,
              CloudSyncRevision.hash(data) == digest else { throw CloudSyncError.invalidData }
        return data
    }

    private func encryptionKey(create: Bool) throws -> SymmetricKey {
        if let value = try keychain.apiKey(for: cacheKeyID) {
            guard let data = Data(base64Encoded: value), data.count == 32 else { throw CloudSyncError.credentialStorage }
            return SymmetricKey(data: data)
        }
        guard create else { throw CloudSyncError.credentialStorage }
        let key = SymmetricKey(size: .bits256)
        try keychain.saveAPIKey(key.withUnsafeBytes { Data($0).base64EncodedString() }, for: cacheKeyID)
        return key
    }

    func removeUnusedPayloads(retaining state: CloudSyncIndex) throws {
        try prepareCache()
        var digests = Set(state.revisions.values.compactMap(\.digest))
        // Archived accounts are intentionally recoverable locally.
        for url in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("previous-account-") {
            let archived = try JSONDecoder().decode(CloudSyncIndex.self, from: Data(contentsOf: url))
            digests.formUnion(archived.revisions.values.compactMap(\.digest))
        }
        for url in try FileManager.default.contentsOfDirectory(at: cache.appending(path: "objects"), includingPropertiesForKeys: nil) {
            let digest = url.lastPathComponent.replacingOccurrences(of: ".sealed", with: "")
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit), !digests.contains(digest) else { continue }
            try FileManager.default.removeItem(at: url)
        }
        // A removed object must not be returned by the file inventory cache.
        inventoryCache = inventoryCache.filter { digests.contains($0.value.digest) }
    }

    func documentDigests() throws -> [String: String] {
        var result: [String: String] = [:]
        let roots = try controlFiles.list(controlFiles.parse("."), recursive: false, maximumEntries: 1_000)
        guard !roots.truncated else { throw CloudSyncError.dataTooLarge }
        for root in roots.entries where ["agent", "appearance", "memory", "skills"].contains(root.path.leafName) {
            guard root.metadata.kind == .directory else { throw CloudSyncError.invalidData }
            try collect(controlFiles, path: root.path.components.joined(separator: "/"), prefix: "control/", into: &result)
        }
        for (directory, prefix) in [("attachments", "attachment"), ("shared", "shared"), ("offloads", "offload")] {
            let path = ".omnibot/\(directory)"
            try collect(workspaceFiles, path: path, prefix: "\(prefix)/", into: &result, stripping: path + "/")
        }
        inventoryCache = inventoryCache.filter { result[$0.key] != nil }
        return result
    }

    private func collect(_ files: WorkspaceDescriptorFileSystem, path: String, prefix: String,
                         into result: inout [String: String], stripping: String = "") throws {
        let listing = try files.list(files.parse(path), recursive: true, maximumEntries: 50_000)
        guard !listing.truncated else { throw CloudSyncError.dataTooLarge }
        for entry in listing.entries {
            let relative = entry.path.components.joined(separator: "/")
            let key = prefix + String(relative.dropFirst(stripping.count))
            guard CloudSyncScope.accepts(key), entry.metadata.kind != .directory else { continue }
            guard entry.metadata.kind == .regular else { throw CloudSyncError.invalidData }
            guard entry.metadata.size <= CloudSyncScope.maximumDocumentBytes else { throw CloudSyncError.dataTooLarge }
            let metadata = entry.metadata
            if let cached = inventoryCache[key], cached.size == metadata.size,
               cached.modifiedAt == metadata.modifiedAt, cached.inode == metadata.inode, cached.device == metadata.device {
                result[key] = cached.digest
                continue
            }
            // Process one file at a time. Do not retain every chat image in
            // memory while collecting a backup (especially on iOS).
            let data = try files.readEntireRegularFile(at: entry.path, maximumBytes: CloudSyncScope.maximumDocumentBytes)
            let digest = try cachePayload(data)
            result[key] = digest
            inventoryCache[key] = CachedFile(size: metadata.size, modifiedAt: metadata.modifiedAt,
                                              inode: metadata.inode, device: metadata.device, digest: digest)
        }
    }

    /// Returns false when a local edit arrived after the snapshot was captured.
    func apply(key: String, data: Data?, expectedDigest: String?) throws -> Bool {
        guard CloudSyncScope.accepts(key) else { throw CloudSyncError.invalidData }
        let files: WorkspaceDescriptorFileSystem
        let path: WorkspaceDescriptorFileSystem.RelativePath
        if key.hasPrefix("control/") {
            files = controlFiles
            path = try files.parse(String(key.dropFirst("control/".count)))
        } else if let prefix = ["attachment", "shared", "offload"].first(where: { key.hasPrefix($0 + "/") }) {
            files = workspaceFiles
            let directory = ["attachment": "attachments", "shared": "shared", "offload": "offloads"][prefix] ?? "attachments"
            path = try files.parse(".omnibot/\(directory)/" + key.dropFirst(prefix.count + 1))
        } else { throw CloudSyncError.invalidData }
        // Read only this document, not the entire attachment inventory for
        // every imported item. Missing files and read failures stay distinct.
        let current = try files.readRegularFileForImport(at: path, maximumBytes: CloudSyncScope.maximumDocumentBytes)
        guard current.map(CloudSyncRevision.hash) == expectedDigest else { return false }
        if let data {
            _ = try files.atomicallyWrite(data, to: path, createParentDirectories: true, appending: false,
                                          maximumBytes: CloudSyncScope.maximumDocumentBytes)
        } else if current != nil {
            try files.removeItem(path)
        }
        return true
    }

    private func prepareCache() throws {
        try FileManager.default.createDirectory(at: cache.appending(path: "objects"), withIntermediateDirectories: true)
    }
}
