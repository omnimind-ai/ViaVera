import Foundation
import Testing
@testable import Via_Vera

@Suite("Terminal screen buffer")
struct TerminalScreenBufferTests {
    @Test("UTF-8 characters survive byte-by-byte output chunks")
    func fragmentedUTF8() {
        var buffer = TerminalScreenBuffer()
        let bytes = Array("你🙂".utf8)

        for byte in bytes {
            buffer.append(Data([byte]))
        }

        #expect(buffer.plainText == "你🙂")
        #expect(!buffer.plainText.contains("�"))
    }

    @Test("Carriage return and backspace move the cursor without deleting cells")
    func carriageReturnAndBackspace() {
        var buffer = TerminalScreenBuffer()

        buffer.append(Data("abc\rX".utf8))
        #expect(buffer.plainText == "Xbc")

        buffer.append(Data([0x08]))
        buffer.append(Data("Y".utf8))
        #expect(buffer.plainText == "Ybc")
    }

    @Test("CSI cursor movement and erase commands update the addressed cells")
    func csiCursorAndEraseCommands() {
        var buffer = TerminalScreenBuffer()
        buffer.resize(TerminalViewportSize(columns: 20, rows: 4))

        buffer.append(Data("abcdef\u{1B}[3D\u{1B}[K".utf8))
        #expect(buffer.plainText == "abc")

        buffer.append(Data("\u{1B}[2;5HZ".utf8))
        #expect(buffer.plainText == "abc\n    Z")

        buffer.append(Data("\u{1B}[2K".utf8))
        #expect(buffer.plainText == "abc\n")

        buffer.append(Data("\u{1B}[2J".utf8))
        #expect(buffer.plainText.isEmpty)
    }

    @Test("Scrollback is bounded and resizing changes future line wrapping")
    func scrollbackBoundsAndResize() {
        var bounded = TerminalScreenBuffer(maximumLines: 4, maximumColumns: 40)
        bounded.resize(TerminalViewportSize(columns: 40, rows: 4))
        bounded.append(Data((1...6).map { "line\($0)" }.joined(separator: "\r\n").utf8))

        #expect(bounded.plainText == "line3\nline4\nline5\nline6")

        let beforeResize = bounded.plainText
        bounded.resize(TerminalViewportSize(columns: 20, rows: 4))
        #expect(bounded.viewport == TerminalViewportSize(columns: 20, rows: 4))
        #expect(bounded.plainText == beforeResize)

        var wrapped = TerminalScreenBuffer(maximumLines: 10, maximumColumns: 40)
        wrapped.resize(TerminalViewportSize(columns: 20, rows: 4))
        wrapped.append(Data((String(repeating: "x", count: 20) + "y").utf8))

        #expect(wrapped.plainText == String(repeating: "x", count: 20) + "\ny")
    }

    @Test("Alternate screen output is discarded when the primary screen is restored")
    func alternateScreenRestoration() {
        var buffer = TerminalScreenBuffer()
        buffer.append(Data("primary\u{1B}[?1049halternate\u{1B}[?1049l".utf8))

        #expect(buffer.plainText == "primary")
    }

    @Test("Character-set escape sequences do not leak their selector into output")
    func characterSetEscapeSequence() {
        var buffer = TerminalScreenBuffer()
        buffer.append(Data("a\u{1B}(Bb".utf8))

        #expect(buffer.plainText == "ab")
    }

    @Test("Device status requests return terminal responses without entering the transcript")
    func deviceStatusResponse() {
        var buffer = TerminalScreenBuffer()
        buffer.append(Data("prompt".utf8))

        let response = buffer.append(Data("\u{1B}[6n".utf8))

        #expect(response == Data("\u{1B}[1;7R".utf8))
        #expect(buffer.plainText == "prompt")
    }

    @Test("Oversized CSI parameters cannot grow or loop beyond configured bounds")
    func oversizedControlSequenceParameters() {
        var buffer = TerminalScreenBuffer(maximumLines: 8, maximumColumns: 40)
        buffer.resize(TerminalViewportSize(columns: 20, rows: 4))

        buffer.append(Data("x\u{1B}[100000000Bz".utf8))
        buffer.append(Data("\u{1B}[100000000@".utf8))
        buffer.append(Data("\u{1B}[100000000X".utf8))
        buffer.append(Data("\u{1B}[100000000S".utf8))

        let lines = buffer.plainText.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count <= 8)
        #expect(lines.allSatisfy { $0.count <= 40 })
    }
}
