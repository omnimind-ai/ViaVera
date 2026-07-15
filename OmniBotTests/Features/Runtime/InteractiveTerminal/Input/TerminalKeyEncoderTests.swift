import Foundation
import Testing
@testable import Via_Vera

@Suite("Terminal key encoder")
struct TerminalKeyEncoderTests {
    @Test("Special keys use their terminal byte sequences")
    func specialKeySequences() {
        let expectations: [(key: TerminalKey, bytes: [UInt8])] = [
            (.escape, [0x1B]),
            (.tab, [0x09]),
            (.slash, [0x2F]),
            (.dash, [0x2D]),
            (.home, [0x1B, 0x5B, 0x48]),
            (.arrowUp, [0x1B, 0x5B, 0x41]),
            (.end, [0x1B, 0x5B, 0x46]),
            (.pageUp, [0x1B, 0x5B, 0x35, 0x7E]),
            (.arrowLeft, [0x1B, 0x5B, 0x44]),
            (.arrowDown, [0x1B, 0x5B, 0x42]),
            (.arrowRight, [0x1B, 0x5B, 0x43]),
            (.pageDown, [0x1B, 0x5B, 0x36, 0x7E]),
            (.enter, [0x0D]),
            (.backspace, [0x7F]),
        ]

        for expectation in expectations {
            #expect(
                Array(TerminalKeyEncoder.data(for: expectation.key)) == expectation.bytes,
                "Unexpected bytes for \(expectation.key.rawValue)"
            )
        }
    }

    @Test("Control and Alternate locks apply together to every character")
    func combinedControlAndAlternateModifiers() {
        var modifiers = TerminalModifierState()
        modifiers.toggleControl()
        modifiers.toggleAlternate()

        let encoded = TerminalKeyEncoder.data(for: "az", modifiers: modifiers)

        #expect(Array(encoded) == [0x1B, 0x01, 0x1B, 0x1A])
    }

    @Test("Application cursor mode uses SS3 arrow sequences")
    func applicationCursorMode() {
        #expect(
            Array(TerminalKeyEncoder.data(for: .arrowUp, applicationCursor: true))
                == [0x1B, 0x4F, 0x41]
        )
        #expect(
            Array(TerminalKeyEncoder.data(for: .arrowLeft, applicationCursor: true))
                == [0x1B, 0x4F, 0x44]
        )
    }

    @Test("Control dash maps to the terminal unit-separator byte")
    func controlDash() {
        var modifiers = TerminalModifierState()
        modifiers.toggleControl()

        #expect(Array(TerminalKeyEncoder.data(for: "-", modifiers: modifiers)) == [0x1F])
    }

    @Test("Pasted text preserves UTF-8 and converts line endings to carriage returns")
    func pastedText() {
        let pasted = "printf '你好🙂'\nnext\r"
        let expected = Data("printf '你好🙂'\rnext\r".utf8)

        #expect(TerminalKeyEncoder.data(for: pasted) == expected)
    }
}
