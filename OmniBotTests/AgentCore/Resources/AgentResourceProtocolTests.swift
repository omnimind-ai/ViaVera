import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent resource protocol")
struct AgentResourceProtocolTests {
    @Test("Round-trips encoded workspace artifacts without exposing host paths")
    func roundTripAndModelSchema() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let file = temporary.paths.attachmentsDirectory.appending(path: "report #1.txt")
        try Data("hello".utf8).write(to: file, options: .atomic)
        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)

        let artifact = try resourceProtocol.artifact(
            for: file,
            sourceTool: "file_write",
            title: "Report]\n[injected"
        )
        #expect(artifact.uri == "omnibot://attachments/report%20%231.txt")
        #expect(artifact.actions.map(\.type) == ["preview", "save"])
        #expect(artifact.actions.allSatisfy { action in
            action.target == artifact.uri && action.payload.isEmpty
        })
        #expect(
            try resourceProtocol.descriptorRelativePath(
                for: #require(URL(string: artifact.uri))
            ).components == [".omnibot", "attachments", "report #1.txt"]
        )
        #expect(
            try resourceProtocol.resolve(#require(URL(string: artifact.uri))).path
                == file.resolvingSymlinksInPath().standardizedFileURL.path
        )
        #expect(artifact.renderMarkdown == "[Report\\] \\[injected](omnibot://attachments/report%20%231.txt)")

        let result = AgentToolExecutionResult(
            content: "Saved report",
            metadata: [
                "toolName": .string("file_write"),
                "toolType": .string("filesystem"),
                "backend": .string("workspace"),
            ],
            artifacts: [artifact],
            workspaceID: "shared",
            actions: artifact.actions
        )
        let modelContent = try result.modelContent()
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(modelContent.utf8)) as? [String: Any]
        )
        #expect(object["summary"] as? String == "Saved report")
        #expect(object["status"] as? String == "completed")
        #expect(object["toolName"] as? String == "file_write")
        #expect(object["toolType"] as? String == "filesystem")
        #expect(object["workspaceId"] as? String == "shared")
        let artifacts = try #require(object["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == 1)
        #expect(artifacts[0]["workspacePath"] as? String == "/workspace/.omnibot/attachments/report #1.txt")
        #expect(artifacts[0]["hostPath"] == nil)
        #expect(!modelContent.contains(temporary.root.path))

        let directlyEncoded = String(
            decoding: try JSONEncoder().encode(result),
            as: UTF8.self
        )
        #expect(!directlyEncoded.contains("hostPath"))
        #expect(!directlyEncoded.contains(temporary.root.path))
    }

    @Test("Rejects URL decoration, encoded separators, traversal, and authority escape")
    func rejectsAmbiguousURLs() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)
        let invalidValues = [
            "omnibot://workspace/file.txt?token=secret",
            "omnibot://workspace/file.txt#fragment",
            "omnibot://user@workspace/file.txt",
            "omnibot://workspace:80/file.txt",
            "omnibot://workspace/%2e%2e/outside.txt",
            "omnibot://attachments/folder%2F..%2Fbrowser/file.txt",
            "omnibot://attachments/folder%5C..%5Cbrowser/file.txt",
            "omnibot://workspace//file.txt",
        ]
        for value in invalidValues {
            let url = try #require(URL(string: value))
            #expect(throws: AgentResourceError.self) {
                try resourceProtocol.resolve(url)
            }
        }
    }

    @Test("Rejects workspace symlinks that resolve outside the workspace")
    func rejectsSymlinkEscape() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let outside = temporary.root.appending(path: "outside.txt")
        try Data("secret".utf8).write(to: outside, options: .atomic)
        let link = temporary.paths.attachmentsDirectory.appending(path: "outside-link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)

        #expect(throws: AgentResourceError.self) {
            try resourceProtocol.resolve(#require(URL(string: "omnibot://attachments/outside-link.txt")))
        }
        #expect(throws: AgentResourceError.self) {
            try resourceProtocol.artifact(for: link, sourceTool: "file_read")
        }
    }

    @Test("Maps structured and macro-enabled artifact preview kinds")
    func androidCompatiblePreviewKinds() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)
        let expectedKinds = [
            "payload.json": "code",
            "feed.xml": "code",
            "settings.yaml": "code",
            "events.ndjson": "code",
            "records.jsonl": "code",
            "letter.docm": "office_word",
            "workbook.xlsm": "office_sheet",
            "slides.pptm": "office_slide",
        ]
        let expectedMIMETypes = [
            "settings.yaml": "application/yaml",
            "events.ndjson": "application/x-ndjson",
            "records.jsonl": "application/x-ndjson",
            "letter.docm": "application/vnd.ms-word.document.macroEnabled.12",
            "workbook.xlsm": "application/vnd.ms-excel.sheet.macroEnabled.12",
            "slides.pptm": "application/vnd.ms-powerpoint.presentation.macroEnabled.12",
        ]

        for (name, expectedKind) in expectedKinds {
            let file = temporary.paths.sharedDirectory.appending(path: name)
            try Data("test".utf8).write(to: file)
            let artifact = try resourceProtocol.artifact(
                for: file,
                sourceTool: "preview_kind_test"
            )
            #expect(artifact.previewKind == expectedKind)
            if let expectedMIMEType = expectedMIMETypes[name] {
                #expect(artifact.mimeType == expectedMIMEType)
            }
        }
    }

    @Test("Preview cache prunes only stale files and enforces bounded capacity")
    func quickLookPreviewCacheMaintenance() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)
        let source = temporary.paths.sharedDirectory.appending(path: "preview.txt")
        try Data("preview body".utf8).write(to: source)
        let resourceURL = try #require(URL(string: try resourceProtocol.resourceURI(for: source)))

        let stale = temporary.paths.previewCacheDirectory.appending(path: "stale.tmp")
        let recent = temporary.paths.previewCacheDirectory.appending(path: "recent.tmp")
        try Data("stale".utf8).write(to: stale)
        try Data("recent".utf8).write(to: recent)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-(25 * 60 * 60))],
            ofItemAtPath: stale.path
        )

        let snapshot = try resourceProtocol.makeQuickLookSnapshot(
            for: resourceURL,
            maximumBytes: 1_024
        )
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(try Data(contentsOf: snapshot) == Data("preview body".utf8))
        resourceProtocol.removeQuickLookSnapshot(snapshot)
        try FileManager.default.removeItem(at: recent)

        #expect(AgentResourceProtocol.maximumQuickLookCacheFiles == 32)
        #expect(AgentResourceProtocol.maximumQuickLookCacheBytes == 512 * 1_024 * 1_024)
        for index in 0..<AgentResourceProtocol.maximumQuickLookCacheFiles {
            try Data([UInt8(index % 255)]).write(
                to: temporary.paths.previewCacheDirectory.appending(path: "recent-\(index).tmp")
            )
        }
        #expect(throws: AgentResourceError.self) {
            _ = try resourceProtocol.makeQuickLookSnapshot(
                for: resourceURL,
                maximumBytes: 1_024
            )
        }
    }

    @Test("Descriptor reads, metadata, and Quick Look snapshots resist atomic symlink swaps")
    func symlinkFlipperCannotRedirectResourceReads() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let safeData = Data("WORKSPACE_RESOURCE_VALUE".utf8)
        let outsideData = Data("OUTSIDE_RESOURCE_CANARY_WITH_DIFFERENT_SIZE".utf8)
        let workspaceFile = temporary.paths.attachmentsDirectory.appending(path: "race.txt")
        try safeData.write(to: workspaceFile)

        let outside = temporary.root.appending(
            path: "resource-read-escape-target",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appending(path: "race.txt")
        try outsideData.write(to: outsideFile)

        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)
        let resourceURL = try #require(URL(string: "omnibot://attachments/race.txt"))
        let flipper = try WorkspaceSymlinkFlipper(
            liveDirectory: temporary.paths.attachmentsDirectory,
            escapeTarget: outside
        )
        var successfulReads = 0
        var successfulArtifacts = 0
        var successfulSnapshots = 0

        do {
            try await flipper.waitForSwaps()
            for index in 0..<160 {
                if let data = try? resourceProtocol.readData(
                    resourceURL,
                    maximumBytes: 1_024
                ) {
                    successfulReads += 1
                    #expect(data == safeData)
                    #expect(data != outsideData)
                }

                if let artifact = try? resourceProtocol.artifact(
                    for: workspaceFile,
                    sourceTool: "race_test"
                ) {
                    successfulArtifacts += 1
                    #expect(artifact.size == Int64(safeData.count))
                    #expect(artifact.workspacePath == "/workspace/.omnibot/attachments/race.txt")
                }

                if index.isMultiple(of: 8),
                   let snapshot = try? resourceProtocol.makeQuickLookSnapshot(
                       for: resourceURL,
                       maximumBytes: 1_024
                   ) {
                    successfulSnapshots += 1
                    let snapshotData = try Data(contentsOf: snapshot)
                    #expect(snapshotData == safeData)
                    #expect(!snapshot.path.hasPrefix(temporary.paths.root.path + "/"))
                    resourceProtocol.removeQuickLookSnapshot(snapshot)
                    #expect(!FileManager.default.fileExists(atPath: snapshot.path))
                }
            }
        } catch {
            try? await flipper.stop()
            throw error
        }
        try await flipper.stop()

        #expect(successfulReads > 0)
        #expect(successfulArtifacts > 0)
        #expect(successfulSnapshots > 0)
        #expect(try Data(contentsOf: outsideFile) == outsideData)

        let finalData = try resourceProtocol.readData(resourceURL, maximumBytes: safeData.count)
        #expect(finalData == safeData)
        #expect(throws: (any Error).self) {
            _ = try resourceProtocol.readData(
                resourceURL,
                maximumBytes: safeData.count - 1
            )
        }
        let finalSnapshot = try resourceProtocol.makeQuickLookSnapshot(
            for: resourceURL,
            maximumBytes: Int64(safeData.count)
        )
        #expect(try Data(contentsOf: finalSnapshot) == safeData)
        resourceProtocol.removeQuickLookSnapshot(finalSnapshot)
        #expect(!FileManager.default.fileExists(atPath: finalSnapshot.path))
    }
}
