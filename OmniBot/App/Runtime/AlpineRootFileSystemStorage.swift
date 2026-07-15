import Foundation

actor AlpineRootFileSystemStorage {
    private let stateDirectory: URL
    private let resetRequestURL: URL

    init(stateDirectory: URL, resetRequestURL: URL) {
        self.stateDirectory = stateDirectory
        self.resetRequestURL = resetRequestURL
    }

    func sizeInBytes() throws -> Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: stateDirectory.path) else { return 0 }

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .totalFileSizeKey,
            .fileSizeKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: stateDirectory,
            includingPropertiesForKeys: Array(resourceKeys)
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }
            let byteCount = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.totalFileSize
                ?? values.fileSize
                ?? 0
            total += Int64(max(byteCount, 0))
        }
        return total
    }

    func scheduleReset() throws {
        try FileManager.default.createDirectory(
            at: resetRequestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("reset\n".utf8).write(to: resetRequestURL, options: .atomic)
    }

    nonisolated static func applyScheduledResetIfNeeded(
        stateDirectory: URL,
        resetRequestURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: resetRequestURL.path) else { return }

        let importingDirectory = URL(
            filePath: stateDirectory.path + ".importing",
            directoryHint: .isDirectory
        )
        for directory in [stateDirectory, importingDirectory]
            where fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.removeItem(at: resetRequestURL)
    }
}
