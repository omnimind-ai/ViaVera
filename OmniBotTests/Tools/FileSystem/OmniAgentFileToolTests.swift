import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent file tools")
struct OmniAgentFileToolTests {
    @Test("Write, read, edit, search, stat, list, and move form a complete workspace flow")
    func completeFileFlow() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        let write = try await executeTool(
            "file_write",
            arguments: titledArguments("Create notes", [
                "path": .string("notes/agent.txt"),
                "content": .string("Hello Agent\nsecond line"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(!write.isError)
        #expect(write.metadata["toolTitle"] == .string("Create notes"))
        #expect(write.metadata["toolName"] == .string("file_write"))
        #expect(write.metadata["toolType"] == .string("filesystem"))
        #expect(write.workspaceID != nil)

        let read = try await executeTool(
            "file_read",
            arguments: titledArguments("Read notes", ["path": .string("notes/agent.txt")]),
            using: executor,
            paths: temporary.paths
        )
        #expect(read.content == "Hello Agent\nsecond line")

        let edit = try await executeTool(
            "file_edit",
            arguments: titledArguments("Edit notes", [
                "path": .string("notes/agent.txt"),
                "old_text": .string("Agent"),
                "new_text": .string("Alpine"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(!edit.isError)

        let search = try await executeTool(
            "file_search",
            arguments: titledArguments("Search notes", [
                "path": .string("notes"),
                "query": .string("alpine"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(search.content.contains("/workspace/notes/agent.txt:1"))

        let stat = try await executeTool(
            "file_stat",
            arguments: titledArguments("Inspect notes", ["path": .string("notes/agent.txt")]),
            using: executor,
            paths: temporary.paths
        )
        #expect(stat.metadata["type"] == .string("file"))

        let list = try await executeTool(
            "file_list",
            arguments: titledArguments("List notes", [
                "path": .string("."),
                "recursive": .bool(true),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(list.content.contains("/workspace/notes/agent.txt"))

        let move = try await executeTool(
            "file_move",
            arguments: titledArguments("Archive notes", [
                "source": .string("notes/agent.txt"),
                "destination": .string("archive/agent.txt"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(!move.isError)

        let moved = try await executeTool(
            "file_read",
            arguments: titledArguments("Read archive", ["path": .string("archive/agent.txt")]),
            using: executor,
            paths: temporary.paths
        )
        #expect(moved.content == "Hello Alpine\nsecond line")
        #expect(!FileManager.default.fileExists(
            atPath: temporary.paths.root.appending(path: "notes/agent.txt").path
        ))
    }

    @Test("A non-unique edit is rejected unless replace_all is explicit")
    func ambiguousEditIsRejected() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)
        _ = try await executeTool(
            "file_write",
            arguments: titledArguments("Seed file", [
                "path": .string("repeat.txt"),
                "content": .string("same same"),
            ]),
            using: executor,
            paths: temporary.paths
        )

        let result = try await executeTool(
            "file_edit",
            arguments: titledArguments("Ambiguous edit", [
                "path": .string("repeat.txt"),
                "old_text": .string("same"),
                "new_text": .string("changed"),
            ]),
            using: executor,
            paths: temporary.paths
        )

        #expect(result.isError)
        #expect(result.content.contains("occurs 2 times"))
    }

    @Test("Append rewrites atomically through the opened parent directory")
    func appendPreservesExistingContents() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        _ = try await executeTool(
            "file_write",
            arguments: titledArguments("Create append target", [
                "path": .string("append/notes.txt"),
                "content": .string("first"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        let append = try await executeTool(
            "file_write",
            arguments: titledArguments("Append target", [
                "path": .string("append/notes.txt"),
                "content": .string(" second"),
                "mode": .string("append"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        let read = try await executeTool(
            "file_read",
            arguments: titledArguments("Read append target", [
                "path": .string("append/notes.txt"),
            ]),
            using: executor,
            paths: temporary.paths
        )

        #expect(!append.isError)
        #expect(append.metadata["fileSizeBytes"] == .number(12))
        #expect(read.content == "first second")
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: temporary.paths.root.appending(path: "append").path
        ) == ["notes.txt"])
    }

    @Test("Move rejects identical, overlapping, and symbolic-link-aliased paths without mutation")
    func moveRejectsPathAliasesAndOverlap() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let root = temporary.paths.root
        let sourceFile = root.appending(path: "source.txt")
        let sourceDirectory = root.appending(path: "tree", directoryHint: .isDirectory)
        try "source".write(to: sourceFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try "child".write(
            to: sourceDirectory.appending(path: "child.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "source-alias.txt"),
            withDestinationURL: sourceFile
        )
        let executor = makeToolExecutor(paths: temporary.paths)

        let identical = try await executeTool(
            "file_move",
            arguments: titledArguments("Reject identical move", [
                "source": .string("source.txt"),
                "destination": .string("source.txt"),
                "overwrite": .bool(true),
            ]),
            using: executor,
            paths: temporary.paths
        )
        let alias = try await executeTool(
            "file_move",
            arguments: titledArguments("Reject alias move", [
                "source": .string("source.txt"),
                "destination": .string("source-alias.txt"),
                "overwrite": .bool(true),
            ]),
            using: executor,
            paths: temporary.paths
        )
        let descendant = try await executeTool(
            "file_move",
            arguments: titledArguments("Reject descendant move", [
                "source": .string("tree"),
                "destination": .string("tree/new/descendant"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        let ancestor = try await executeTool(
            "file_move",
            arguments: titledArguments("Reject ancestor move", [
                "source": .string("tree/child.txt"),
                "destination": .string("tree"),
                "overwrite": .bool(true),
            ]),
            using: executor,
            paths: temporary.paths
        )

        for result in [identical, alias, descendant, ancestor] {
            #expect(result.isError)
        }
        #expect(try String(contentsOf: sourceFile, encoding: .utf8) == "source")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "source-alias.txt").path))
        #expect(FileManager.default.fileExists(atPath: sourceDirectory.appending(path: "child.txt").path))
        #expect(!FileManager.default.fileExists(atPath: sourceDirectory.appending(path: "new").path))
    }

    @Test("Move overwrite never removes a destination directory")
    func moveDoesNotOverwriteDirectories() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let root = temporary.paths.root
        let source = root.appending(path: "source.txt")
        let destination = root.appending(path: "destination", directoryHint: .isDirectory)
        let marker = destination.appending(path: "keep.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "keep".write(to: marker, atomically: true, encoding: .utf8)
        let executor = makeToolExecutor(paths: temporary.paths)

        let result = try await executeTool(
            "file_move",
            arguments: titledArguments("Reject directory replacement", [
                "source": .string("source.txt"),
                "destination": .string("destination"),
                "overwrite": .bool(true),
            ]),
            using: executor,
            paths: temporary.paths
        )

        #expect(result.isError)
        #expect(result.content.contains("Overwriting directories is not supported"))
        #expect(try String(contentsOf: source, encoding: .utf8) == "source")
        #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
    }

    @Test("Move can replace an existing regular file without a delete-first window")
    func moveReplacesRegularFile() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let root = temporary.paths.root
        let source = root.appending(path: "source.txt")
        let destination = root.appending(path: "destination.txt")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "old".write(to: destination, atomically: true, encoding: .utf8)
        let executor = makeToolExecutor(paths: temporary.paths)

        let result = try await executeTool(
            "file_move",
            arguments: titledArguments("Replace file", [
                "source": .string("source.txt"),
                "destination": .string("destination.txt"),
                "overwrite": .bool(true),
            ]),
            using: executor,
            paths: temporary.paths
        )

        #expect(!result.isError)
        #expect(result.metadata["overwroteExisting"] == .bool(true))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
    }

    @Test("Rejects path components that cannot safely round-trip through resource output")
    func rejectsUnsafeResourcePathCharacters() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        let unsafePaths = [
            "folder\\artifact.txt",
            "folder/new\nline.txt",
            "folder/bidi-\u{202E}txt.exe",
            "folder/c1-\u{0085}.txt",
        ]
        for path in unsafePaths {
            let result = try await executeTool(
                "file_write",
                arguments: titledArguments("Reject incompatible path", [
                    "path": .string(path),
                    "content": .string("must not be written"),
                ]),
                using: executor,
                paths: temporary.paths
            )

            #expect(result.isError)
            #expect(!FileManager.default.fileExists(
                atPath: temporary.paths.root.appending(path: path).path
            ))
        }
    }
}
