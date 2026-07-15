import Foundation

nonisolated enum InteractiveTerminalState: Equatable, Sendable {
    case idle
    case preparing(message: String)
    case running(processIdentifier: Int)
    case stopping
    case stopped(exitCode: Int)
    case failed(message: String)

    var acceptsInput: Bool {
        if case .running = self {
            true
        } else {
            false
        }
    }

    var showsBlockingOverlay: Bool {
        switch self {
        case .idle, .preparing, .stopping, .failed:
            true
        case .running, .stopped:
            false
        }
    }
}
