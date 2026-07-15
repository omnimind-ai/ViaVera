import Foundation
import CryptoKit
import Observation
import Synchronization

#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class AlpineRuntime {
    private static let expectedRootFileSystemSHA256 = "f31202c4070c4ef7de9e157e1bd01cb4da3a2150035d74ea5372c5e86f1efac1"

    private(set) var state: AlpineRuntimeState = .idle

    @ObservationIgnored
    private var preparationTask: Task<Void, Error>?

    private let rootFileSystemArchiveURL: URL
    private let stateDirectory: URL
    private let workspaceDirectory: URL

    init(
        rootFileSystemArchiveURL: URL,
        stateDirectory: URL,
        workspaceDirectory: URL
    ) {
        self.rootFileSystemArchiveURL = rootFileSystemArchiveURL
        self.stateDirectory = stateDirectory
        self.workspaceDirectory = workspaceDirectory
    }

    var isReady: Bool {
        if case .ready = state {
            true
        } else {
            false
        }
    }

    func prepare() async throws {
        if isReady || OmniISHRuntime.isReady {
            state = .ready
            return
        }

        if let preparationTask {
            try await preparationTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.performPreparation()
        }
        preparationTask = task

        do {
            try await task.value
            preparationTask = nil
        } catch {
            preparationTask = nil
            state = .failed(message: error.localizedDescription)
            throw error
        }
    }

    private func performPreparation() async throws {
        if isReady || OmniISHRuntime.isReady {
            state = .ready
            return
        }

        state = .preparing(progress: 0, message: "正在校验 Alpine…")
        let archiveData = try Data(contentsOf: rootFileSystemArchiveURL, options: .mappedIfSafe)
        let archiveDigest = SHA256.hash(data: archiveData).map { byte in
            String(byte, radix: 16).leftPadded(to: 2, with: "0")
        }.joined()
        guard archiveDigest == Self.expectedRootFileSystemSHA256 else {
            state = .failed(message: AlpineRuntimeValidationError.rootFileSystemChecksumMismatch.localizedDescription)
            throw AlpineRuntimeValidationError.rootFileSystemChecksumMismatch
        }

        state = .preparing(progress: 0, message: "正在准备 Alpine…")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            OmniISHRuntime.prepare(
                withRootFileSystemArchive: rootFileSystemArchiveURL,
                expectedSHA256: Self.expectedRootFileSystemSHA256,
                stateDirectory: stateDirectory,
                workspaceDirectory: workspaceDirectory
            ) { [weak self] progress, message in
                Task { @MainActor [weak self] in
                    self?.state = .preparing(progress: progress, message: message)
                }
            } completion: { [weak self] error in
                Task { @MainActor [weak self] in
                    if let error {
                        self?.state = .failed(message: error.localizedDescription)
                        continuation.resume(throwing: error)
                    } else {
                        self?.state = .ready
                        continuation.resume()
                    }
                }
            }
        }
    }

    func execute(
        _ command: String,
        workingDirectory: String = "/workspace",
        environment: [String: String] = [:],
        timeout: Duration = .seconds(120),
        onLine: (@MainActor (String, Bool) -> Void)? = nil
    ) async -> AlpineCommandResult {
        if !isReady {
            do {
                try await prepare()
            } catch {
                return AlpineCommandResult(
                    executionID: UUID(),
                    processIdentifier: -1,
                    exitCode: -1,
                    standardOutput: "",
                    standardError: "",
                    duration: .zero,
                    failureDescription: error.localizedDescription
                )
            }
        }

        let cancellationState = Mutex(ExecutionCancellationState())
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let identifier = OmniISHRuntime.executeCommand(
                    command,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    timeout: timeout.timeInterval
                ) { line, isStandardError in
                    onLine?(line, isStandardError)
                } completion: { result in
                    let seconds = max(result.duration, 0)
                    let executionID = cancellationState.withLock { $0.identifier ?? UUID() }
                    continuation.resume(returning: AlpineCommandResult(
                        executionID: executionID,
                        processIdentifier: Int(result.processIdentifier),
                        exitCode: Int(result.exitCode),
                        standardOutput: result.standardOutput,
                        standardError: result.standardError,
                        duration: .seconds(seconds),
                        failureDescription: result.error?.localizedDescription
                    ))
                }
                let shouldCancel = cancellationState.withLock { state in
                    state.identifier = identifier
                    return state.cancelRequested
                }
                if shouldCancel {
                    OmniISHRuntime.cancelExecution(identifier)
                }
            }
        } onCancel: {
            let identifier = cancellationState.withLock { state in
                state.cancelRequested = true
                return state.identifier
            }
            if let identifier {
                OmniISHRuntime.cancelExecution(identifier)
            }
        }
    }

    @discardableResult
    func startInteractiveTerminal(
        workingDirectory: String = "/workspace",
        environment: [String: String] = [:],
        viewport: TerminalViewportSize = TerminalViewportSize(),
        onOutput: @escaping @MainActor @Sendable (
            Data,
            @escaping @MainActor @Sendable () -> Void
        ) -> Void,
        onStarted: @escaping @MainActor @Sendable (Int, Error?) -> Void,
        onExit: @escaping @MainActor @Sendable (Int, Error?) -> Void
    ) -> UUID {
        OmniISHRuntime.startInteractiveTerminal(
            withWorkingDirectory: workingDirectory,
            environment: environment,
            columns: Int32(viewport.columns),
            rows: Int32(viewport.rows)
        ) { data, acknowledge in
            MainActor.assumeIsolated {
                onOutput(data) {
                    acknowledge()
                }
            }
        } startedHandler: { processIdentifier, error in
            MainActor.assumeIsolated {
                onStarted(Int(processIdentifier), error)
            }
        } exitHandler: { exitCode, error in
            MainActor.assumeIsolated {
                onExit(Int(exitCode), error)
            }
        }
    }

    func sendInput(_ data: Data, toInteractiveTerminal identifier: UUID) {
        guard !data.isEmpty else { return }
        OmniISHRuntime.sendInput(data, toInteractiveTerminal: identifier)
    }

    func resizeInteractiveTerminal(
        _ identifier: UUID,
        to viewport: TerminalViewportSize
    ) {
        OmniISHRuntime.resizeInteractiveTerminal(
            identifier,
            columns: Int32(viewport.columns),
            rows: Int32(viewport.rows)
        )
    }

    func stopInteractiveTerminal(_ identifier: UUID) {
        OmniISHRuntime.stopInteractiveTerminal(identifier)
    }

    #if os(iOS)
    func viewForInteractiveTerminal(_ identifier: UUID) -> UIView? {
        OmniISHRuntime.view(forInteractiveTerminal: identifier)
    }

    func setInteractiveTerminalModifiers(
        control: Bool,
        alternate: Bool,
        for identifier: UUID
    ) {
        OmniISHRuntime.setControlModifier(
            control,
            alternateModifier: alternate,
            forInteractiveTerminal: identifier
        )
    }

    func sendInputKey(_ key: TerminalKey, toInteractiveTerminal identifier: UUID) {
        let upstreamKey: OmniISHTerminalInputKey = switch key {
        case .escape: .escape
        case .tab: .tab
        case .slash: .slash
        case .dash: .dash
        case .home: .home
        case .arrowUp: .arrowUp
        case .end: .end
        case .pageUp: .pageUp
        case .arrowLeft: .arrowLeft
        case .arrowDown: .arrowDown
        case .arrowRight: .arrowRight
        case .pageDown: .pageDown
        case .enter: .enter
        case .backspace: .backspace
        }
        OmniISHRuntime.send(upstreamKey, toInteractiveTerminal: identifier)
    }

    func sendText(_ text: String, toInteractiveTerminal identifier: UUID) {
        guard !text.isEmpty else { return }
        OmniISHRuntime.sendText(text, toInteractiveTerminal: identifier)
    }
    #endif

    #if DEBUG
    func debugGuestProcessCount(for executionID: UUID) -> Int {
        Int(OmniISHRuntime.debugGuestProcessCount(forExecution: executionID))
    }
    #endif
}

private struct ExecutionCancellationState: Sendable {
    var identifier: UUID?
    var cancelRequested = false
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        if count >= length {
            self
        } else {
            String(repeating: character, count: length - count) + self
        }
    }
}
