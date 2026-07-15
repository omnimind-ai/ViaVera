import Foundation
import Observation

#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class InteractiveTerminalModel {
    private(set) var state: InteractiveTerminalState = .idle
#if os(macOS)
    private(set) var displayText = ""
#endif
    private(set) var modifiers = TerminalModifierState()
    private(set) var keyboardFocusRequestID: UInt = 0

#if os(iOS)
    private(set) var nativeTerminalView: UIView?
#endif

#if os(macOS)
    @ObservationIgnored private var screen = TerminalScreenBuffer()
#endif

    @ObservationIgnored
    private var viewport = TerminalViewportSize()

    @ObservationIgnored
    private var sessionIdentifier: UUID?

    @ObservationIgnored
    private var sessionGeneration = UUID()

    @ObservationIgnored
    private var shouldRestartAfterStop = false

    @ObservationIgnored
    private var stopWasRequested = false

    private let runtime: AlpineRuntime

    init(runtime: AlpineRuntime) {
        self.runtime = runtime
#if os(macOS)
        screen.resize(viewport)
#endif
    }

    var isControlLocked: Bool {
        modifiers.isControlLocked
    }

    var isAlternateLocked: Bool {
        modifiers.isAlternateLocked
    }

    func startIfNeeded() async {
        guard state == .idle else { return }
        await startSession()
    }

    func startNewSession() {
        shouldRestartAfterStop = false
        if let sessionIdentifier {
            shouldRestartAfterStop = true
            stopWasRequested = true
            state = .stopping
            refreshDisplay()
            runtime.stopInteractiveTerminal(sessionIdentifier)
            return
        }

        sessionGeneration = UUID()
        Task {
            await startSession()
        }
    }

    func stop() {
        guard let sessionIdentifier else { return }
        shouldRestartAfterStop = false
        stopWasRequested = true
        state = .stopping
        refreshDisplay()
        runtime.stopInteractiveTerminal(sessionIdentifier)
    }

    func send(_ text: String) {
        guard state.acceptsInput else { return }
#if os(iOS)
        guard let sessionIdentifier else { return }
        runtime.sendText(text, toInteractiveTerminal: sessionIdentifier)
#else
        sendRaw(TerminalKeyEncoder.data(for: text, modifiers: modifiers))
#endif
    }

    func send(_ key: TerminalKey) {
        guard state.acceptsInput else { return }
#if os(iOS)
        guard let sessionIdentifier else { return }
        runtime.sendInputKey(key, toInteractiveTerminal: sessionIdentifier)
#else
        sendRaw(TerminalKeyEncoder.data(
            for: key,
            modifiers: modifiers,
            applicationCursor: false
        ))
#endif
    }

    func sendTerminalInput(_ data: Data) {
        guard state.acceptsInput else { return }
        sendRaw(data)
    }

    func activate(_ accessoryKey: TerminalAccessoryKey) {
        switch accessoryKey {
        case .control:
            modifiers.toggleControl()
            synchronizeUpstreamModifiers()
        case .alternate:
            modifiers.toggleAlternate()
            synchronizeUpstreamModifiers()
        case .key(let key):
            send(key)
        }
    }

    func requestKeyboardFocus() {
        keyboardFocusRequestID &+= 1
    }

    func updateViewport(_ viewport: TerminalViewportSize) {
        guard self.viewport != viewport else { return }
        self.viewport = viewport
#if os(macOS)
        screen.resize(viewport)
        refreshDisplay()
#endif
        if let sessionIdentifier {
            runtime.resizeInteractiveTerminal(sessionIdentifier, to: viewport)
        }
    }

    private func startSession() async {
        guard sessionIdentifier == nil else { return }
        let generation = UUID()
        sessionGeneration = generation
        stopWasRequested = false
        shouldRestartAfterStop = false
        state = .preparing(message: "正在准备 Alpine…")
        modifiers.reset()
#if os(macOS)
        screen.reset()
        screen.resize(viewport)
#endif
#if os(iOS)
        nativeTerminalView = nil
#endif
        refreshDisplay()

        do {
            try await runtime.prepare()
        } catch {
            guard sessionGeneration == generation else { return }
            state = .failed(message: error.localizedDescription)
#if os(macOS)
            screen.appendSystemMessage("[无法启动终端：\(error.localizedDescription)]")
#endif
            refreshDisplay()
            return
        }

        guard sessionGeneration == generation else { return }
        state = .preparing(message: "正在启动交互式 shell…")

        let identifier = runtime.startInteractiveTerminal(
            viewport: viewport,
            onOutput: { [weak self] data, acknowledge in
                guard let self, self.sessionGeneration == generation else {
                    acknowledge()
                    return
                }
#if os(iOS)
                // iSH's upstream Terminal owns the renderer and consumes PTY
                // output directly on iOS. The callback remains for the shared
                // macOS runtime API but must never retain iOS output.
                _ = data
                acknowledge()
#else
                self.receive(data, acknowledge: acknowledge)
#endif
            },
            onStarted: { [weak self] processIdentifier, error in
                guard let self, self.sessionGeneration == generation else { return }
                self.handleStarted(processIdentifier: processIdentifier, error: error)
            },
            onExit: { [weak self] exitCode, error in
                guard let self, self.sessionGeneration == generation else { return }
                self.handleExit(exitCode: exitCode, error: error)
            }
        )
        sessionIdentifier = identifier
    }

#if os(macOS)
    private func receive(
        _ data: Data,
        acknowledge: @escaping @MainActor @Sendable () -> Void
    ) {
        let response = screen.append(data)
        refreshDisplay()
        sendRaw(response)
        acknowledge()
    }
#endif

    private func handleStarted(processIdentifier: Int, error: Error?) {
        if let error {
            sessionIdentifier = nil
            state = .failed(message: error.localizedDescription)
#if os(macOS)
            screen.appendSystemMessage("[无法启动终端：\(error.localizedDescription)]")
#endif
        } else {
#if os(iOS)
            guard let sessionIdentifier,
                  let terminalView = runtime.viewForInteractiveTerminal(sessionIdentifier) else {
                state = .failed(message: "iSH 终端视图创建失败。")
                if let sessionIdentifier {
                    runtime.stopInteractiveTerminal(sessionIdentifier)
                }
                refreshDisplay()
                return
            }
            nativeTerminalView = terminalView
            synchronizeUpstreamModifiers()
#endif
            state = .running(processIdentifier: processIdentifier)
        }
        refreshDisplay()
    }

    private func handleExit(exitCode: Int, error: Error?) {
        sessionIdentifier = nil
#if os(iOS)
        nativeTerminalView = nil
#endif
        let requestedRestart = shouldRestartAfterStop
        shouldRestartAfterStop = false

        if let error, !stopWasRequested {
            state = .failed(message: error.localizedDescription)
#if os(macOS)
            screen.appendSystemMessage("[终端异常结束：\(error.localizedDescription)]")
#endif
        } else {
            state = .stopped(exitCode: exitCode)
#if os(macOS)
            screen.appendSystemMessage("[终端进程已结束，退出码 \(exitCode)]")
#endif
        }
        stopWasRequested = false
        refreshDisplay()

        if requestedRestart {
            Task {
                await startSession()
            }
        }
    }

    private func sendRaw(_ data: Data) {
        guard let sessionIdentifier, !data.isEmpty else { return }
        runtime.sendInput(data, toInteractiveTerminal: sessionIdentifier)
    }

    private func synchronizeUpstreamModifiers() {
#if os(iOS)
        guard let sessionIdentifier else { return }
        runtime.setInteractiveTerminalModifiers(
            control: modifiers.isControlLocked,
            alternate: modifiers.isAlternateLocked,
            for: sessionIdentifier
        )
#endif
    }

    private func refreshDisplay() {
#if os(macOS)
        let renderedText = screen.renderedText(showCursor: state.acceptsInput)
        guard displayText != renderedText else { return }
        displayText = renderedText
#endif
    }
}
