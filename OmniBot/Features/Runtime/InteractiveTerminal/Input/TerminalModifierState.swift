import Foundation

nonisolated struct TerminalModifierState: Equatable, Sendable {
    private(set) var isControlLocked = false
    private(set) var isAlternateLocked = false

    mutating func toggleControl() {
        isControlLocked.toggle()
    }

    mutating func toggleAlternate() {
        isAlternateLocked.toggle()
    }

    mutating func reset() {
        isControlLocked = false
        isAlternateLocked = false
    }
}
