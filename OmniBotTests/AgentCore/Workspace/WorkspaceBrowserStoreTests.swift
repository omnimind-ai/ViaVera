import Foundation
import Testing
@testable import Via_Vera

@Suite("Workspace browser store")
struct WorkspaceBrowserStoreTests {
    @Test("Lists hidden workspace contents, folders, and files")
    func listsWorkspaceContents() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }

        let fileSystem = WorkspaceDescriptorFileSystem(paths: temporary.paths)
        let folder = try fileSystem.parse("Projects")
        let file = try fileSystem.parse("notes.txt")
        let nestedFile = try fileSystem.parse("Projects/readme.md")
        try fileSystem.createDirectory(folder)
        try fileSystem.atomicallyWrite(
            Data("notes".utf8),
            to: file,
            createParentDirectories: false,
            appending: false,
            maximumBytes: 1_024
        )
        try fileSystem.atomicallyWrite(
            Data("readme".utf8),
            to: nestedFile,
            createParentDirectories: false,
            appending: false,
            maximumBytes: 1_024
        )

        let store = WorkspaceBrowserStore(paths: temporary.paths)
        let rootItems = try store.items(in: .root)
        let projects = try #require(rootItems.first { $0.name == "Projects" })
        let notes = try #require(rootItems.first { $0.name == "notes.txt" })

        #expect(rootItems.contains { $0.name == ".omnibot" })
        #expect(projects.kind == .directory)
        #expect(notes.kind == .file)
        #expect(notes.byteCount == 5)

        let projectItems = try store.items(in: projects.path)
        #expect(projectItems.map(\.name) == ["readme.md"])
    }

    @Test("Creates and removes a bounded Quick Look snapshot")
    func createsPreviewSnapshot() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }

        let fileSystem = WorkspaceDescriptorFileSystem(paths: temporary.paths)
        let file = try fileSystem.parse("preview.txt")
        try fileSystem.atomicallyWrite(
            Data("workspace preview".utf8),
            to: file,
            createParentDirectories: false,
            appending: false,
            maximumBytes: 1_024
        )

        let store = WorkspaceBrowserStore(paths: temporary.paths)
        let item = try #require(
            try store.items(in: .root).first { $0.name == "preview.txt" }
        )
        let snapshotURL = try store.makePreviewSnapshot(for: item)

        #expect(try Data(contentsOf: snapshotURL) == Data("workspace preview".utf8))

        store.removePreviewSnapshot(snapshotURL)
        #expect(!FileManager.default.fileExists(atPath: snapshotURL.path))
    }
}
