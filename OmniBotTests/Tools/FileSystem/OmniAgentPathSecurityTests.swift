import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent tool path security")
struct OmniAgentPathSecurityTests {
    @Test("File tools reject traversal, host absolute paths, and escaping symlinks")
    func rejectsWorkspaceEscapeAttempts() async throws {
        let temporary = try makeTemporaryWorkspace()
        let outside = FileManager.default.temporaryDirectory
            .appending(path: "OmniBotOutside-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporary.root)
            try? FileManager.default.removeItem(at: outside)
        }
        let secret = outside.appending(path: "secret.txt")
        try "outside secret".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: temporary.paths.root.appending(path: "escape"),
            withDestinationURL: outside
        )
        let executor = makeToolExecutor(paths: temporary.paths)

        for path in ["../secret.txt", "/etc/passwd", "escape/secret.txt"] {
            let result = try await executeTool(
                "file_read",
                arguments: titledArguments("Read unsafe path", ["path": .string(path)]),
                using: executor,
                paths: temporary.paths
            )
            #expect(result.isError, "Expected \(path) to be rejected")
        }

        let writeResult = try await executeTool(
            "file_write",
            arguments: titledArguments("Write unsafe path", [
                "path": .string("escape/created.txt"),
                "content": .string("must not escape"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(writeResult.isError)
        #expect(!FileManager.default.fileExists(atPath: outside.appending(path: "created.txt").path))
    }

    @Test("Workspace absolute paths remain supported")
    func workspaceAbsolutePathIsSupported() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let executor = makeToolExecutor(paths: temporary.paths)

        let write = try await executeTool(
            "file_write",
            arguments: titledArguments("Write workspace file", [
                "path": .string("/workspace/safe.txt"),
                "content": .string("safe"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        let read = try await executeTool(
            "file_read",
            arguments: titledArguments("Read workspace file", [
                "path": .string("/workspace/safe.txt"),
            ]),
            using: executor,
            paths: temporary.paths
        )

        #expect(!write.isError)
        #expect(read.content == "safe")
    }

    @Test("Concurrent symlink replacement cannot redirect descriptor-relative file tools into Control")
    func symlinkFlipperCannotReachControl() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }

        let workspace = temporary.paths.root
        let control = temporary.paths.controlRoot
        let flip = workspace.appending(path: "flip", directoryHint: .isDirectory)
        let sources = workspace.appending(path: "move-sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)

        let controlSecret = String(repeating: "CONTROL_READ_CANARY", count: 256)
        let controlEditOriginal = "workspace CONTROL_EDIT_CANARY"
        try controlSecret.write(
            to: control.appending(path: "secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        try controlEditOriginal.write(
            to: control.appending(path: "edit.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "CONTROL_LIST_CANARY".write(
            to: control.appending(path: "control-only.txt"),
            atomically: true,
            encoding: .utf8
        )
        let initialControlNames = try Set(
            FileManager.default.contentsOfDirectory(atPath: control.path)
        )

        // Begin in the hostile state so the test covers the no-follow path even
        // before the concurrent loop gets scheduled.
        try FileManager.default.createSymbolicLink(at: flip, withDestinationURL: control)
        let flipper = Task.detached(priority: .high) {
            let fileManager = FileManager()
            while !Task.isCancelled {
                try? fileManager.removeItem(at: flip)
                try? fileManager.createDirectory(at: flip, withIntermediateDirectories: false)
                try? "workspace-safe".write(
                    to: flip.appending(path: "secret.txt"),
                    atomically: false,
                    encoding: .utf8
                )
                try? "workspace editable".write(
                    to: flip.appending(path: "edit.txt"),
                    atomically: false,
                    encoding: .utf8
                )
                try? await Task.sleep(for: .microseconds(100))

                try? fileManager.removeItem(at: flip)
                try? fileManager.createSymbolicLink(at: flip, withDestinationURL: control)
                try? await Task.sleep(for: .microseconds(100))
            }
            try? fileManager.removeItem(at: flip)
        }
        defer { flipper.cancel() }

        let executor = makeToolExecutor(paths: temporary.paths)
        await Task.yield()
        for index in 0..<160 {
            let read = try await executeTool(
                "file_read",
                arguments: titledArguments("Race read", ["path": .string("flip/secret.txt")]),
                using: executor,
                paths: temporary.paths
            )
            if !read.isError {
                #expect(!read.content.contains("CONTROL_READ_CANARY"))
            }

            let write = try await executeTool(
                "file_write",
                arguments: titledArguments("Race write", [
                    "path": .string("flip/created.txt"),
                    "content": .string("workspace write \(index)"),
                ]),
                using: executor,
                paths: temporary.paths
            )
            if !write.isError {
                #expect(!FileManager.default.fileExists(
                    atPath: control.appending(path: "created.txt").path
                ))
            }

            let edit = try await executeTool(
                "file_edit",
                arguments: titledArguments("Race edit", [
                    "path": .string("flip/edit.txt"),
                    "old_text": .string("workspace"),
                    "new_text": .string("edited"),
                    "replace_all": .bool(true),
                ]),
                using: executor,
                paths: temporary.paths
            )
            if !edit.isError {
                #expect(try String(
                    contentsOf: control.appending(path: "edit.txt"),
                    encoding: .utf8
                ) == controlEditOriginal)
            }

            let stat = try await executeTool(
                "file_stat",
                arguments: titledArguments("Race stat", ["path": .string("flip/secret.txt")]),
                using: executor,
                paths: temporary.paths
            )
            if !stat.isError, case let .number(size)? = stat.metadata["sizeBytes"] {
                #expect(Int(size) != controlSecret.utf8.count)
            }

            let list = try await executeTool(
                "file_list",
                arguments: titledArguments("Race list", [
                    "path": .string("flip"),
                    "recursive": .bool(true),
                ]),
                using: executor,
                paths: temporary.paths
            )
            if !list.isError {
                #expect(!list.content.contains("control-only.txt"))
            }

            let search = try await executeTool(
                "file_search",
                arguments: titledArguments("Race search", [
                    "path": .string("flip"),
                    "query": .string("CONTROL_"),
                ]),
                using: executor,
                paths: temporary.paths
            )
            if !search.isError {
                #expect(!search.content.contains("CONTROL_"))
            }

            let sourceName = "move-sources/source-\(index).txt"
            try "move \(index)".write(
                to: workspace.appending(path: sourceName),
                atomically: false,
                encoding: .utf8
            )
            _ = try await executeTool(
                "file_move",
                arguments: titledArguments("Race move", [
                    "source": .string(sourceName),
                    "destination": .string("flip/moved-\(index).txt"),
                ]),
                using: executor,
                paths: temporary.paths
            )
        }

        flipper.cancel()
        _ = await flipper.result

        #expect(try String(
            contentsOf: control.appending(path: "secret.txt"),
            encoding: .utf8
        ) == controlSecret)
        #expect(try String(
            contentsOf: control.appending(path: "edit.txt"),
            encoding: .utf8
        ) == controlEditOriginal)
        let controlNames = try Set(FileManager.default.contentsOfDirectory(atPath: control.path))
        #expect(controlNames == initialControlNames)
    }
}
