import Foundation

public actor WorkspaceAttachmentImporter {
    private static let maximumFilesPerImport = 16
    private static let maximumFileBytes: Int64 = 256 * 1_024 * 1_024

    private let paths: WorkspacePaths
    private let resourceProtocol: AgentResourceProtocol
    private let workspaceFileSystem: WorkspaceDescriptorFileSystem

    public init(paths: WorkspacePaths) {
        self.paths = paths
        resourceProtocol = AgentResourceProtocol(paths: paths)
        workspaceFileSystem = WorkspaceDescriptorFileSystem(paths: paths)
    }

    public func importFiles(_ sourceURLs: [URL]) throws -> [AgentArtifact] {
        guard sourceURLs.count <= Self.maximumFilesPerImport else {
            throw AttachmentImportError.tooManyFiles(sourceURLs.count)
        }
        try paths.prepare()
        let attachments = try workspaceFileSystem.parse(".omnibot/attachments")

        var copiedPaths: [WorkspaceDescriptorFileSystem.RelativePath] = []
        do {
            var artifacts: [AgentArtifact] = []
            for sourceURL in sourceURLs {
                try Task.checkCancellation()
                let didAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                let values = try sourceURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                ])
                guard values.isRegularFile == true else {
                    throw AttachmentImportError.notARegularFile(sourceURL.lastPathComponent)
                }
                let size = Int64(values.fileSize ?? 0)
                guard size <= Self.maximumFileBytes else {
                    throw AttachmentImportError.fileTooLarge(sourceURL.lastPathComponent)
                }

                let destinationPath: WorkspaceDescriptorFileSystem.RelativePath
                do {
                    destinationPath = try workspaceFileSystem.copyRegularFileUnique(
                        from: sourceURL,
                        in: attachments,
                        preferredName: sourceURL.lastPathComponent,
                        maximumBytes: Self.maximumFileBytes
                    )
                } catch WorkspaceDescriptorFileSystem.HostWriteLimitError.sourceFileTooLarge {
                    throw AttachmentImportError.fileTooLarge(sourceURL.lastPathComponent)
                }
                copiedPaths.append(destinationPath)
                let destination = destinationPath.components.reduce(paths.root) {
                    partial, component in
                    partial.appending(path: component)
                }
                artifacts.append(try resourceProtocol.artifact(
                    for: destination,
                    sourceTool: "user_attachment",
                    title: sourceURL.lastPathComponent
                ))
            }
            return artifacts
        } catch {
            for copiedPath in copiedPaths {
                try? workspaceFileSystem.removeItem(copiedPath)
            }
            throw error
        }
    }

    public func importPayloads(
        _ payloads: [WorkspaceAttachmentPayload]
    ) throws -> [AgentArtifact] {
        guard payloads.count <= Self.maximumFilesPerImport else {
            throw AttachmentImportError.tooManyFiles(payloads.count)
        }
        try paths.prepare()
        let attachments = try workspaceFileSystem.parse(".omnibot/attachments")

        var copiedPaths: [WorkspaceDescriptorFileSystem.RelativePath] = []
        do {
            var artifacts: [AgentArtifact] = []
            for payload in payloads {
                try Task.checkCancellation()
                let destinationPath: WorkspaceDescriptorFileSystem.RelativePath
                do {
                    destinationPath = try workspaceFileSystem.atomicallyWriteUnique(
                        payload.data,
                        in: attachments,
                        preferredName: payload.preferredName,
                        maximumBytes: Int(Self.maximumFileBytes)
                    )
                } catch WorkspaceDescriptorFileSystem.HostWriteLimitError.sourceFileTooLarge {
                    throw AttachmentImportError.fileTooLarge(payload.preferredName)
                }
                copiedPaths.append(destinationPath)
                let destination = destinationPath.components.reduce(paths.root) {
                    partial, component in
                    partial.appending(path: component)
                }
                artifacts.append(try resourceProtocol.artifact(
                    for: destination,
                    sourceTool: "user_attachment",
                    title: payload.preferredName
                ))
            }
            return artifacts
        } catch {
            for copiedPath in copiedPaths {
                try? workspaceFileSystem.removeItem(copiedPath)
            }
            throw error
        }
    }
}
