import Foundation
import Testing
@testable import Via_Vera

@Suite("Alpine Rootfs management")
@MainActor
struct AlpineRootFileSystemManagerTests {
    @Test("Size refresh and reset preserve files until the next launch")
    func sizeAndScheduledReset() async throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "AlpineRootFileSystemManagerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateDirectory = container.appending(path: "AlpineRoot", directoryHint: .isDirectory)
        let importingDirectory = URL(
            filePath: stateDirectory.path + ".importing",
            directoryHint: .isDirectory
        )
        let resetRequestURL = container.appending(
            path: "Control/.omnibot/alpine-rootfs-reset-requested",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: container) }

        try FileManager.default.createDirectory(
            at: stateDirectory.appending(path: "data", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xA5, count: 4_096).write(
            to: stateDirectory.appending(path: "data/rootfs-block")
        )

        let manager = AlpineRootFileSystemManager(
            stateDirectory: stateDirectory,
            resetRequestURL: resetRequestURL
        )
        await manager.refreshSize()

        #expect(manager.sizeInBytes != nil)
        #expect(manager.sizeInBytes ?? 0 >= 4_096)
        #expect(manager.errorMessage == nil)

        await manager.scheduleReset()

        #expect(manager.isResetScheduled)
        #expect(FileManager.default.fileExists(atPath: resetRequestURL.path))
        #expect(FileManager.default.fileExists(atPath: stateDirectory.path))

        try FileManager.default.createDirectory(
            at: importingDirectory,
            withIntermediateDirectories: true
        )
        try AlpineRootFileSystemStorage.applyScheduledResetIfNeeded(
            stateDirectory: stateDirectory,
            resetRequestURL: resetRequestURL
        )

        #expect(!FileManager.default.fileExists(atPath: stateDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: importingDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: resetRequestURL.path))
    }
}
