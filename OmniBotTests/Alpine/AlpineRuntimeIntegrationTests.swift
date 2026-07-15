import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import Via_Vera

@Suite(.serialized)
@MainActor
struct AlpineRuntimeIntegrationTests {
    @Test
    func commandLifecycleCancellationAndBounds() async throws {
        let archiveURL = try #require(Bundle.main.url(
            forResource: "alpine-minirootfs-3.21.0-aarch64",
            withExtension: "tar.gz"
        ))
        let container = FileManager.default.temporaryDirectory
            .appending(path: "OmniBot-AlpineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let applicationSupport = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first).appending(path: "OmniBot", directoryHint: .isDirectory)
        let runtimeWasAlreadyPrepared = OmniISHRuntime.isReady
        let stateDirectory = runtimeWasAlreadyPrepared
            ? applicationSupport.appending(path: "AlpineRoot", directoryHint: .isDirectory)
            : container.appending(path: "root", directoryHint: .isDirectory)
        let workspaceDirectory = runtimeWasAlreadyPrepared
            ? applicationSupport.appending(path: "workspace", directoryHint: .isDirectory)
            : container.appending(path: "workspace", directoryHint: .isDirectory)
        // The embedded runtime intentionally has process lifetime. Its SQLite
        // handles therefore remain open until the test host exits; deleting
        // this temporary root in a defer would invalidate live file handles.

        if !runtimeWasAlreadyPrepared {
            // Simulate a process being terminated during the old direct-import
            // layout. Presence of meta.db/data without the SHA marker must
            // never be accepted as a bootable root filesystem.
            try FileManager.default.createDirectory(
                at: stateDirectory.appending(path: "data", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            try Data("incomplete".utf8).write(
                to: stateDirectory.appending(path: "meta.db"),
                options: .atomic
            )
        }

        let runtime = AlpineRuntime(
            rootFileSystemArchiveURL: archiveURL,
            stateDirectory: stateDirectory,
            workspaceDirectory: workspaceDirectory
        )

        async let firstPreparation: Void = runtime.prepare()
        async let secondPreparation: Void = runtime.prepare()
        try await firstPreparation
        try await secondPreparation
        #expect(runtime.isReady)

        let completionMarker = stateDirectory.appending(path: ".omnibot-rootfs-complete")
        #expect(FileManager.default.fileExists(atPath: completionMarker.path))
        #expect(!FileManager.default.fileExists(
            atPath: stateDirectory.path + ".importing"
        ))

        for index in 0..<32 {
            let result = await runtime.execute("printf 'run-\(index)'")
            #expect(result.succeeded)
            #expect(result.standardOutput == "run-\(index)")
        }

        let systemInformationResult = await runtime.execute(
            "uname -a && echo \"---\" && cat /etc/os-release 2>/dev/null || cat /etc/alpine-release 2>/dev/null && echo \"---\" && hostname && echo \"---\" && lscpu 2>/dev/null || cat /proc/cpuinfo | head -20 && echo \"---\" && free -h && echo \"---\" && df -h / /workspace 2>/dev/null",
            timeout: .seconds(5)
        )
        #expect(systemInformationResult.succeeded)
        #expect(systemInformationResult.standardOutput.contains("Alpine Linux"))
        #expect(systemInformationResult.standardOutput.contains("Filesystem"))

        let backgroundResult = await runtime.execute(
            "(sleep 30 >/dev/null 2>&1 &) & sleep 30 >/dev/null 2>&1 & printf background",
            timeout: .seconds(5)
        )
        #expect(backgroundResult.succeeded)
        #expect(backgroundResult.standardOutput == "background")
        #if DEBUG
        #expect(runtime.debugGuestProcessCount(for: backgroundResult.executionID) == 0)
        #endif

        var liveCallbackCount = 0
        var liveCallbackBytes = 0
        var largestLiveCallbackBytes = 0
        var observedStandardErrorValues = Set<Bool>()
        let highRateOutputResult = await runtime.execute(
            "(yes stdout | head -n 30000) & (yes stderr | head -n 30000 >&2) & wait",
            onLine: { line, isStandardError in
                let byteCount = line.utf8.count
                liveCallbackCount += 1
                liveCallbackBytes += byteCount
                largestLiveCallbackBytes = max(largestLiveCallbackBytes, byteCount)
                observedStandardErrorValues.insert(isStandardError)
            }
        )
        #expect(highRateOutputResult.succeeded)
        #expect(highRateOutputResult.standardOutput.utf8.count == 210_000)
        #expect(highRateOutputResult.standardError.utf8.count == 210_000)
        #expect(liveCallbackCount > 0)
        #expect(liveCallbackCount < 200)
        #expect(liveCallbackBytes <= 256 * 1024)
        #expect(largestLiveCallbackBytes <= 256 * 1024)
        #expect(observedStandardErrorValues == [false, true])
        #if DEBUG
        #expect(runtime.debugGuestProcessCount(for: highRateOutputResult.executionID) == 0)
        #endif

        let unbrokenOutputResult = await runtime.execute("yes x | tr -d '\\n' | head -c 131072")
        #expect(unbrokenOutputResult.succeeded)
        #expect(unbrokenOutputResult.standardOutput.utf8.count == 131_072)
        #if DEBUG
        #expect(runtime.debugGuestProcessCount(for: unbrokenOutputResult.executionID) == 0)
        #endif

        let oversizedResult = await runtime.execute(String(repeating: "x", count: 64 * 1024))
        #expect(!oversizedResult.succeeded)
        #expect(oversizedResult.processIdentifier == -1)
        #expect(oversizedResult.failureDescription?.contains("64 KiB") == true)

        let timedOutResult = await runtime.execute(
            "sleep 30 & (sleep 30 &) & wait",
            timeout: .milliseconds(100)
        )
        #expect(!timedOutResult.succeeded)
        #expect(timedOutResult.failureDescription?.contains("timed out") == true)
        #if DEBUG
        let timedOutResidualCount = runtime.debugGuestProcessCount(for: timedOutResult.executionID)
        #expect(timedOutResidualCount == 0)
        #endif

        let cancelledTask = Task { @MainActor in
            await runtime.execute("sleep 30 & wait")
        }
        try await Task.sleep(for: .milliseconds(50))
        cancelledTask.cancel()
        let cancelledResult = await cancelledTask.value
        #expect(!cancelledResult.succeeded)
        #expect(cancelledResult.failureDescription?.contains("cancelled") == true)
        #if DEBUG
        let cancelledResidualCount = runtime.debugGuestProcessCount(for: cancelledResult.executionID)
        #expect(cancelledResidualCount == 0)
        #endif

        var terminalOutput = Data()
        var terminalProcessIdentifier: Int?
        var terminalStartError: String?
        var terminalExitCode: Int?
        var terminalExitError: String?
        let terminalIdentifier = runtime.startInteractiveTerminal(
            viewport: TerminalViewportSize(columns: 80, rows: 24),
            onOutput: { data, acknowledge in
                terminalOutput.append(data)
                acknowledge()
            },
            onStarted: { processIdentifier, error in
                terminalProcessIdentifier = processIdentifier
                terminalStartError = error?.localizedDescription
            },
            onExit: { exitCode, error in
                terminalExitCode = exitCode
                terminalExitError = error?.localizedDescription
            }
        )
        let terminalDidStart = await waitUntil {
            terminalProcessIdentifier != nil || terminalStartError != nil
        }
        #expect(terminalDidStart)
        #expect(terminalProcessIdentifier != nil)
        #expect(terminalStartError == nil)

        #if os(iOS)
        let upstreamTerminalView = try #require(
            runtime.viewForInteractiveTerminal(terminalIdentifier)
        )
        #expect(String(describing: type(of: upstreamTerminalView)) == "TerminalView")
        #expect(!upstreamTerminalView.subviews.isEmpty)
        #expect(upstreamTerminalView.bounds.width > 0)
        #expect(upstreamTerminalView.bounds.height > 0)
        #endif

        runtime.sendInput(
            Data((
                "test -t 0 && test -t 1 && echo PTY_OK; "
                    + "test -c /dev/tty && test -c /dev/ptmx && echo DEV_OK; "
                    + "tty; pwd; stty size; "
                    + "printf '\\033[31mUTF8:中文\\033[0m\\n'\r"
            ).utf8),
            toInteractiveTerminal: terminalIdentifier
        )
        let terminalProbeCompleted = await waitUntil {
            let output = String(decoding: terminalOutput, as: UTF8.self)
            return output.contains("PTY_OK")
                && output.contains("DEV_OK")
                && output.contains("/workspace")
                && output.contains("24 80")
                && output.contains("UTF8:中文")
        }
        if !terminalProbeCompleted {
            Issue.record(
                "Interactive PTY probe output: \(String(decoding: terminalOutput, as: UTF8.self))"
            )
        }
        #expect(terminalProbeCompleted)

        runtime.resizeInteractiveTerminal(
            terminalIdentifier,
            to: TerminalViewportSize(columns: 100, rows: 35)
        )
        runtime.sendInput(
            Data("stty size; echo RESIZED\r".utf8),
            toInteractiveTerminal: terminalIdentifier
        )
        let terminalResizeCompleted = await waitUntil {
            let output = String(decoding: terminalOutput, as: UTF8.self)
            return output.contains("35 100") && output.contains("RESIZED")
        }
        #expect(terminalResizeCompleted)

        runtime.sendInput(
            Data("echo SLEEP_STARTED; sleep 30\r".utf8),
            toInteractiveTerminal: terminalIdentifier
        )
        #expect(await waitUntil {
            String(decoding: terminalOutput, as: UTF8.self).contains("SLEEP_STARTED")
        })
        try await Task.sleep(for: .milliseconds(100))
#if os(iOS)
        runtime.setInteractiveTerminalModifiers(
            control: true,
            alternate: false,
            for: terminalIdentifier
        )
        runtime.sendText("c", toInteractiveTerminal: terminalIdentifier)
        runtime.setInteractiveTerminalModifiers(
            control: false,
            alternate: false,
            for: terminalIdentifier
        )
        runtime.sendText("echo CTRL_C_OK", toInteractiveTerminal: terminalIdentifier)
        runtime.sendInputKey(.enter, toInteractiveTerminal: terminalIdentifier)
#else
        runtime.sendInput(
            Data([0x03]),
            toInteractiveTerminal: terminalIdentifier
        )
        runtime.sendInput(
            Data("echo CTRL_C_OK\r".utf8),
            toInteractiveTerminal: terminalIdentifier
        )
#endif
        let terminalAcceptedControlC = await waitUntil {
            String(decoding: terminalOutput, as: UTF8.self).contains("CTRL_C_OK")
        }
        if !terminalAcceptedControlC {
            Issue.record(
                "Interactive PTY Ctrl-C output: \(String(decoding: terminalOutput, as: UTF8.self))"
            )
        }
        #expect(terminalAcceptedControlC)

        runtime.sendInput(
            Data("exit\r".utf8),
            toInteractiveTerminal: terminalIdentifier
        )
        let terminalDidExit = await waitUntil {
            terminalExitCode != nil || terminalExitError != nil
        }
        #expect(terminalDidExit)
        #expect(terminalExitCode == 0)
        #expect(terminalExitError == nil)
        #if DEBUG
        #expect(runtime.debugGuestProcessCount(for: terminalIdentifier) == 0)
        #endif

        let acknowledgementGate = TerminalAcknowledgementGate()
        var backpressuredTerminalDidStart = false
        var backpressuredTerminalExitCode: Int?
        var backpressuredTerminalExitError: String?
        let backpressuredTerminalIdentifier = runtime.startInteractiveTerminal(
            onOutput: { _, acknowledge in
                if acknowledgementGate.isReleased {
                    acknowledge()
                } else {
                    acknowledgementGate.withheld = acknowledge
                }
            },
            onStarted: { _, error in
                backpressuredTerminalDidStart = error == nil
            },
            onExit: { exitCode, error in
                backpressuredTerminalExitCode = exitCode
                backpressuredTerminalExitError = error?.localizedDescription
            }
        )
        #expect(await waitUntil { backpressuredTerminalDidStart })
        #expect(await waitUntil { acknowledgementGate.withheld != nil })
        runtime.sendInput(
            Data("exit\r".utf8),
            toInteractiveTerminal: backpressuredTerminalIdentifier
        )
        try await Task.sleep(for: .milliseconds(100))
        #expect(backpressuredTerminalExitCode == nil)
        #expect(backpressuredTerminalExitError == nil)

        acknowledgementGate.isReleased = true
        let acknowledgement = acknowledgementGate.withheld
        acknowledgementGate.withheld = nil
        acknowledgement?()
        #expect(await waitUntil {
            backpressuredTerminalExitCode != nil || backpressuredTerminalExitError != nil
        })
        #expect(backpressuredTerminalExitCode == 0)
        #expect(backpressuredTerminalExitError == nil)
        #if DEBUG
        #expect(runtime.debugGuestProcessCount(for: backpressuredTerminalIdentifier) == 0)
        #endif

        var stoppedTerminalOutput = Data()
        var stoppedTerminalDidStart = false
        var stoppedTerminalExitCode: Int?
        var stoppedTerminalExitError: String?
        let stoppedTerminalIdentifier = runtime.startInteractiveTerminal(
            onOutput: { data, acknowledge in
                stoppedTerminalOutput.append(data)
                acknowledge()
            },
            onStarted: { _, error in
                stoppedTerminalDidStart = error == nil
            },
            onExit: { exitCode, error in
                stoppedTerminalExitCode = exitCode
                stoppedTerminalExitError = error?.localizedDescription
            }
        )
        #expect(await waitUntil { stoppedTerminalDidStart })
        runtime.sendInput(
            Data("sleep 30 & echo BACKGROUND_STARTED\r".utf8),
            toInteractiveTerminal: stoppedTerminalIdentifier
        )
        #expect(await waitUntil {
            String(decoding: stoppedTerminalOutput, as: UTF8.self)
                .contains("BACKGROUND_STARTED")
        })
        runtime.stopInteractiveTerminal(stoppedTerminalIdentifier)
        #expect(await waitUntil {
            stoppedTerminalExitCode != nil || stoppedTerminalExitError != nil
        })
        #expect(stoppedTerminalExitError?.contains("stopped") == true)
        #if DEBUG
        #expect(runtime.debugGuestProcessCount(for: stoppedTerminalIdentifier) == 0)
        #endif

        let finalResult = await runtime.execute("printf alive")
        #expect(finalResult.succeeded)
        #expect(finalResult.standardOutput == "alive")
        #if DEBUG
        #expect(runtime.debugGuestProcessCount(for: finalResult.executionID) == 0)
        #endif
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor
private final class TerminalAcknowledgementGate {
    var isReleased = false
    var withheld: (@MainActor @Sendable () -> Void)?
}
