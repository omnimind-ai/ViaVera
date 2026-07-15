import Foundation

nonisolated enum TerminalKey: String, Hashable, Identifiable, Sendable {
    case escape
    case tab
    case slash
    case dash
    case home
    case arrowUp
    case end
    case pageUp
    case arrowLeft
    case arrowDown
    case arrowRight
    case pageDown
    case enter
    case backspace

    var id: String { rawValue }
}
