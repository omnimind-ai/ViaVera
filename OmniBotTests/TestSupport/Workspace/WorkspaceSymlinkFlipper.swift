import Darwin
import Foundation

private actor WorkspaceSymlinkSwapCounter {
    private var count = 0

    func recordSwap() {
        count += 1
    }

    func currentCount() -> Int {
        count
    }
}

/// Atomically alternates one workspace directory name between its real
/// directory and a same-parent symbolic link to an escape target. Unlike a
/// remove/recreate race, `RENAME_SWAP` leaves no missing-name window, making
/// descriptor-walk regression tests deterministic enough for CI.
struct WorkspaceSymlinkFlipper: Sendable {
    private let parentDescriptor: Int32
    private let liveName: String
    private let alternateName: String
    private let task: Task<Int, Never>
    private let counter: WorkspaceSymlinkSwapCounter

    init(liveDirectory: URL, escapeTarget: URL) throws {
        let parent = liveDirectory.deletingLastPathComponent()
        liveName = liveDirectory.lastPathComponent
        alternateName = ".symlink-flipper-\(UUID().uuidString)"
        counter = WorkspaceSymlinkSwapCounter()

        let alternate = parent.appending(path: alternateName)
        try FileManager.default.createSymbolicLink(
            at: alternate,
            withDestinationURL: escapeTarget
        )

        let descriptor = parent.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return -1 }
            return Darwin.open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            try? FileManager.default.removeItem(at: alternate)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        parentDescriptor = descriptor

        let capturedLiveName = liveName
        let capturedAlternateName = alternateName
        let capturedCounter = counter
        task = Task.detached(priority: .high) {
            var successfulSwaps = 0
            while !Task.isCancelled {
                let result = capturedLiveName.withCString { livePointer in
                    capturedAlternateName.withCString { alternatePointer in
                        Darwin.renameatx_np(
                            descriptor,
                            livePointer,
                            descriptor,
                            alternatePointer,
                            UInt32(RENAME_SWAP)
                        )
                    }
                }
                if result == 0 {
                    successfulSwaps += 1
                    await capturedCounter.recordSwap()
                }
                try? await Task.sleep(for: .microseconds(50))
            }
            return successfulSwaps
        }
    }

    func waitForSwaps(_ minimum: Int = 4) async throws {
        for _ in 0..<500 {
            if await counter.currentCount() >= minimum {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw POSIXError(.ETIMEDOUT)
    }

    /// Cancels the flipper, restores the real directory at its original name,
    /// removes the alternate symlink, and closes the pinned parent descriptor.
    func stop() async throws {
        task.cancel()
        let successfulSwaps = await task.value
        if !successfulSwaps.isMultiple(of: 2) {
            let result = liveName.withCString { livePointer in
                alternateName.withCString { alternatePointer in
                    Darwin.renameatx_np(
                        parentDescriptor,
                        livePointer,
                        parentDescriptor,
                        alternatePointer,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard result == 0 else {
                let code = errno
                Darwin.close(parentDescriptor)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        }
        let unlinkResult = alternateName.withCString {
            Darwin.unlinkat(parentDescriptor, $0, 0)
        }
        let unlinkError = errno
        Darwin.close(parentDescriptor)
        guard unlinkResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: unlinkError) ?? .EIO)
        }
    }
}
