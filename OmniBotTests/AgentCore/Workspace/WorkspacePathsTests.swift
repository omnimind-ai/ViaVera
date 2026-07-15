import Foundation
import Testing
@testable import Via_Vera

@Suite("Workspace paths")
struct WorkspacePathsTests {
    @Test("Prepares the Agent directory layout and rejects traversal")
    func layoutAndTraversal() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }

        #expect(FileManager.default.fileExists(atPath: temporary.paths.agentDirectory.path))
        #expect(FileManager.default.fileExists(atPath: temporary.paths.shortMemoryDirectory.path))
        #expect(FileManager.default.fileExists(atPath: temporary.paths.attachmentsDirectory.path))
        #expect(FileManager.default.fileExists(atPath: temporary.paths.browserDirectory.path))
        #expect(FileManager.default.fileExists(atPath: temporary.paths.authoritativeSkillsDirectory.path))
        #expect(FileManager.default.fileExists(atPath: temporary.paths.previewCacheDirectory.path))
        #expect(FileManager.default.fileExists(atPath: temporary.paths.skillsDirectory.path))
        #expect(!temporary.paths.controlRoot.path.hasPrefix(temporary.paths.root.path + "/"))
        #expect(!temporary.paths.authoritativeSkillsDirectory.path.hasPrefix(
            temporary.paths.root.path + "/"
        ))
        #expect(!temporary.paths.previewCacheDirectory.path.hasPrefix(
            temporary.paths.root.path + "/"
        ))
        #expect(try temporary.paths.resolve(relativePath: "shared/result.txt").path.hasPrefix(temporary.root.path))

        #expect(throws: WorkspacePathError.self) {
            try temporary.paths.resolve(relativePath: "../../outside.txt")
        }
        #expect(throws: WorkspacePathError.self) {
            try temporary.paths.resolve(relativePath: "/etc/passwd")
        }
    }

    @Test("Rejects a private control directory below the shared workspace")
    func rejectsControlDirectoryInsideWorkspace() throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "OmniBotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: container) }

        let workspace = container.appending(path: "workspace", directoryHint: .isDirectory)
        let paths = WorkspacePaths(
            root: workspace,
            controlRoot: workspace.appending(path: "private", directoryHint: .isDirectory)
        )

        #expect(throws: WorkspacePathError.self) {
            try paths.prepare()
        }
    }

    @Test("Rejects model-visible directory symlink replacement")
    func rejectsManagedDirectorySymlink() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        try FileManager.default.removeItem(at: temporary.paths.workspaceOmniBotDirectory)
        try FileManager.default.createSymbolicLink(
            at: temporary.paths.workspaceOmniBotDirectory,
            withDestinationURL: temporary.paths.controlRoot
        )

        #expect(throws: WorkspacePathError.self) {
            try temporary.paths.prepare()
        }
    }

    @Test("Quarantines legacy control data instead of trusting it with credentials")
    func quarantinesLegacyControlDirectory() throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "OmniBotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: container) }

        let workspace = container.appending(path: "workspace", directoryHint: .isDirectory)
        let legacyAgent = workspace
            .appending(path: ".omnibot", directoryHint: .isDirectory)
            .appending(path: "agent", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyAgent, withIntermediateDirectories: true)
        try Data("legacy-provider-state".utf8).write(
            to: legacyAgent.appending(path: "providers.json"),
            options: .atomic
        )

        let paths = WorkspacePaths(
            root: workspace,
            controlRoot: container.appending(path: "control", directoryHint: .isDirectory)
        )
        try paths.prepare()

        #expect(FileManager.default.fileExists(
            atPath: workspace.appending(path: ".omnibot").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: workspace
                .appending(path: ".omnibot", directoryHint: .isDirectory)
                .appending(path: "agent", directoryHint: .isDirectory)
                .path
        ))
        #expect(!FileManager.default.fileExists(atPath: paths.providerConfigFile.path))

        let quarantine = paths.controlRoot.appending(path: "Quarantine", directoryHint: .isDirectory)
        let quarantinedItems = try FileManager.default.contentsOfDirectory(
            at: quarantine,
            includingPropertiesForKeys: nil
        )
        #expect(quarantinedItems.count == 1)
        let quarantinedProvider = quarantinedItems[0]
            .appending(path: "agent", directoryHint: .isDirectory)
            .appending(path: "providers.json")
        #expect(try String(contentsOf: quarantinedProvider, encoding: .utf8) == "legacy-provider-state")
    }

    @Test("Imports user attachments into the model-visible attachment subtree")
    func importsAttachments() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let source = temporary.root.appending(path: "input.txt")
        try Data("attachment body".utf8).write(to: source, options: .atomic)
        let importer = WorkspaceAttachmentImporter(paths: temporary.paths)

        let artifacts = try await importer.importFiles([source])

        let artifact = try #require(artifacts.first)
        #expect(artifact.workspacePath == "/workspace/.omnibot/attachments/input.txt")
        #expect(artifact.uri == "omnibot://attachments/input.txt")
        #expect(FileManager.default.fileExists(
            atPath: temporary.paths.attachmentsDirectory.appending(path: "input.txt").path
        ))
        let modelValue = try AgentToolExecutionResult(
            content: "Imported",
            artifacts: artifacts
        ).modelContent()
        #expect(!modelValue.contains(temporary.root.path))
    }

    @Test("Imports in-memory photo payloads into the attachment subtree")
    func importsAttachmentPayloads() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let imageData = Data("bounded image payload".utf8)
        let importer = WorkspaceAttachmentImporter(paths: temporary.paths)

        let artifacts = try await importer.importPayloads([
            WorkspaceAttachmentPayload(
                data: imageData,
                preferredName: "照片-1.png"
            ),
        ])

        let artifact = try #require(artifacts.first)
        #expect(artifact.workspacePath == "/workspace/.omnibot/attachments/照片-1.png")
        #expect(artifact.previewKind == "image")
        #expect(try Data(contentsOf: URL(fileURLWithPath: artifact.hostPath)) == imageData)
    }

    @Test("A background symlink swap cannot redirect attachment imports")
    func attachmentImportSymlinkFlipper() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let source = temporary.root.appending(path: "attachment-source.txt")
        let sourceData = Data("bounded attachment payload".utf8)
        try sourceData.write(to: source, options: .atomic)

        let outside = temporary.root.appending(
            path: "attachment-escape-target",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let canary = outside.appending(path: "canary.txt")
        try "ATTACHMENT_ESCAPE_CANARY".write(to: canary, atomically: true, encoding: .utf8)
        let initialOutsideNames = try Set(
            FileManager.default.contentsOfDirectory(atPath: outside.path)
        )

        let importer = WorkspaceAttachmentImporter(paths: temporary.paths)
        let flipper = try WorkspaceSymlinkFlipper(
            liveDirectory: temporary.paths.attachmentsDirectory,
            escapeTarget: outside
        )
        do {
            try await flipper.waitForSwaps()
            for _ in 0..<80 {
                _ = try? await importer.importFiles([source])
            }
        } catch {
            try? await flipper.stop()
            throw error
        }
        try await flipper.stop()

        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: outside.path)) == initialOutsideNames)
        #expect(try String(contentsOf: canary, encoding: .utf8) == "ATTACHMENT_ESCAPE_CANARY")

        let artifact = try #require(try await importer.importFiles([source]).first)
        #expect(try Data(contentsOf: URL(fileURLWithPath: artifact.hostPath)) == sourceData)
    }
}
