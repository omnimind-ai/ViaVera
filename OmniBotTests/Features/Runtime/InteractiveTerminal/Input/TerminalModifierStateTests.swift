import Foundation
import Testing
@testable import Via_Vera

@Suite("Terminal modifier state")
struct TerminalModifierStateTests {
    @Test("Control stays locked across input until toggled again")
    func controlLockPersistsUntilToggledOff() {
        var modifiers = TerminalModifierState()

        modifiers.toggleControl()
        #expect(modifiers.isControlLocked)
        #expect(Array(TerminalKeyEncoder.data(for: "c", modifiers: modifiers)) == [0x03])
        #expect(Array(TerminalKeyEncoder.data(for: "d", modifiers: modifiers)) == [0x04])
        #expect(modifiers.isControlLocked)

        modifiers.toggleControl()
        #expect(!modifiers.isControlLocked)
        #expect(Array(TerminalKeyEncoder.data(for: "c", modifiers: modifiers)) == [0x63])
    }

    @Test("Alternate stays locked independently until toggled again")
    func alternateLockPersistsUntilToggledOff() {
        var modifiers = TerminalModifierState()

        modifiers.toggleAlternate()
        #expect(modifiers.isAlternateLocked)
        #expect(Array(TerminalKeyEncoder.data(for: "x", modifiers: modifiers)) == [0x1B, 0x78])
        #expect(Array(TerminalKeyEncoder.data(for: "y", modifiers: modifiers)) == [0x1B, 0x79])
        #expect(modifiers.isAlternateLocked)

        modifiers.toggleAlternate()
        #expect(!modifiers.isAlternateLocked)
        #expect(Array(TerminalKeyEncoder.data(for: "x", modifiers: modifiers)) == [0x78])
    }

    @Test("Reset releases both persistent modifier locks")
    func resetReleasesBothLocks() {
        var modifiers = TerminalModifierState()
        modifiers.toggleControl()
        modifiers.toggleAlternate()

        modifiers.reset()

        #expect(!modifiers.isControlLocked)
        #expect(!modifiers.isAlternateLocked)
    }
}
