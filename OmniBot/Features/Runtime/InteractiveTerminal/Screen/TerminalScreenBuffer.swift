import Foundation

nonisolated struct TerminalScreenBuffer: Sendable {
    private static let replacementCharacter: Character = "�"

    private let maximumLines: Int
    private let maximumColumns: Int

    private(set) var viewport = TerminalViewportSize()
    private var lines: [[Character]] = [[]]
    private var cursorRow = 0
    private var cursorColumn = 0
    private var savedCursorRow = 0
    private var savedCursorColumn = 0
    private var primaryScreenLines: [[Character]]?
    private var primaryCursorRow = 0
    private var primaryCursorColumn = 0
    private var parserState = 0
    private var controlSequence: [UInt8] = []
    private var pendingResponse = Data()
    private var pendingUTF8: [UInt8] = []
    private var expectedUTF8ByteCount = 0

    init(maximumLines: Int = 1_200, maximumColumns: Int = 240) {
        self.maximumLines = max(1, maximumLines)
        self.maximumColumns = max(20, maximumColumns)
    }

    var plainText: String {
        lines.map { String($0) }.joined(separator: "\n")
    }

    func renderedText(showCursor: Bool) -> String {
        guard showCursor, lines.indices.contains(cursorRow) else {
            return plainText
        }

        var renderedLines = lines
        while renderedLines[cursorRow].count < cursorColumn {
            renderedLines[cursorRow].append(" ")
        }
        let insertionColumn = min(cursorColumn, renderedLines[cursorRow].count)
        renderedLines[cursorRow].insert("▌", at: insertionColumn)
        return renderedLines.map { String($0) }.joined(separator: "\n")
    }

    mutating func resize(_ viewport: TerminalViewportSize) {
        self.viewport = viewport
        cursorColumn = min(cursorColumn, viewport.columns - 1)
        trimLinesToBounds()
    }

    mutating func reset() {
        lines = [[]]
        cursorRow = 0
        cursorColumn = 0
        savedCursorRow = 0
        savedCursorColumn = 0
        primaryScreenLines = nil
        primaryCursorRow = 0
        primaryCursorColumn = 0
        parserState = 0
        controlSequence.removeAll(keepingCapacity: true)
        pendingResponse.removeAll(keepingCapacity: true)
        pendingUTF8.removeAll(keepingCapacity: true)
        expectedUTF8ByteCount = 0
    }

    @discardableResult
    mutating func append(_ data: Data) -> Data {
        for byte in data {
            consume(byte)
        }
        let response = pendingResponse
        pendingResponse.removeAll(keepingCapacity: true)
        return response
    }

    mutating func appendSystemMessage(_ message: String) {
        flushIncompleteUTF8()
        parserState = 0
        controlSequence.removeAll(keepingCapacity: true)
        if !lines[cursorRow].isEmpty || cursorColumn > 0 {
            cursorColumn = 0
            lineFeed()
        }
        for character in message {
            write(character)
        }
        cursorColumn = 0
        lineFeed()
    }

    private mutating func consume(_ byte: UInt8) {
        switch parserState {
        case 1:
            consumeEscape(byte)
        case 2:
            consumeControlSequence(byte)
        case 3:
            consumeOperatingSystemCommand(byte)
        case 4:
            parserState = byte == 0x5C ? 0 : 3
        case 5:
            parserState = 0
        default:
            consumeGround(byte)
        }
    }

    private mutating func consumeGround(_ byte: UInt8) {
        if expectedUTF8ByteCount > 0 {
            if (byte & 0xC0) == 0x80 {
                pendingUTF8.append(byte)
                if pendingUTF8.count == expectedUTF8ByteCount {
                    writeDecodedUTF8()
                }
                return
            }

            flushIncompleteUTF8()
            consumeGround(byte)
            return
        }

        switch byte {
        case 0x08:
            cursorColumn = max(0, cursorColumn - 1)
        case 0x09:
            tab()
        case 0x0A, 0x0B, 0x0C:
            lineFeed()
        case 0x0D:
            cursorColumn = 0
        case 0x1B:
            parserState = 1
        case 0x00...0x1F, 0x7F:
            break
        case 0x20...0x7E:
            write(Character(String(decoding: [byte], as: UTF8.self)))
        case 0xC2...0xDF:
            pendingUTF8 = [byte]
            expectedUTF8ByteCount = 2
        case 0xE0...0xEF:
            pendingUTF8 = [byte]
            expectedUTF8ByteCount = 3
        case 0xF0...0xF4:
            pendingUTF8 = [byte]
            expectedUTF8ByteCount = 4
        default:
            write(Self.replacementCharacter)
        }
    }

    private mutating func consumeEscape(_ byte: UInt8) {
        parserState = 0
        switch byte {
        case 0x5B:
            parserState = 2
            controlSequence.removeAll(keepingCapacity: true)
        case 0x5D:
            parserState = 3
        case 0x23, 0x28, 0x29, 0x2A, 0x2B, 0x25:
            parserState = 5
        case 0x37:
            saveCursor()
        case 0x38:
            restoreCursor()
        case 0x44:
            lineFeed()
        case 0x45:
            cursorColumn = 0
            lineFeed()
        case 0x4D:
            cursorRow = max(viewportBaseRow, cursorRow - 1)
        case 0x63:
            reset()
        default:
            break
        }
    }

    private mutating func consumeControlSequence(_ byte: UInt8) {
        controlSequence.append(byte)
        guard (0x40...0x7E).contains(byte) else {
            if controlSequence.count > 128 {
                parserState = 0
                controlSequence.removeAll(keepingCapacity: true)
            }
            return
        }

        parserState = 0
        handleControlSequence(finalByte: byte)
        controlSequence.removeAll(keepingCapacity: true)
    }

    private mutating func consumeOperatingSystemCommand(_ byte: UInt8) {
        if byte == 0x07 {
            parserState = 0
        } else if byte == 0x1B {
            parserState = 4
        }
    }

    private mutating func handleControlSequence(finalByte: UInt8) {
        let parameterBytes = controlSequence.dropLast()
        let rawParameterText = String(decoding: parameterBytes, as: UTF8.self)
        let isPrivateMode = rawParameterText.hasPrefix("?")
        let parameterText = rawParameterText
            .trimmingCharacters(in: CharacterSet(charactersIn: "?=>!"))
        let parameters = parameterText.split(separator: ";", omittingEmptySubsequences: false)
            .map { rawValue in
                min(max(Int(rawValue) ?? 0, 0), maximumControlParameter)
            }

        switch finalByte {
        case 0x40:
            insertBlankCharacters(parameter(parameters, at: 0, defaultValue: 1))
        case 0x41:
            cursorRow = max(
                viewportBaseRow,
                cursorRow - parameter(parameters, at: 0, defaultValue: 1)
            )
        case 0x42:
            moveCursorDown(parameter(parameters, at: 0, defaultValue: 1))
        case 0x43:
            cursorColumn = min(
                viewport.columns - 1,
                cursorColumn + parameter(parameters, at: 0, defaultValue: 1)
            )
        case 0x44:
            cursorColumn = max(
                0,
                cursorColumn - parameter(parameters, at: 0, defaultValue: 1)
            )
        case 0x45:
            moveCursorDown(parameter(parameters, at: 0, defaultValue: 1))
            cursorColumn = 0
        case 0x46:
            cursorRow = max(
                viewportBaseRow,
                cursorRow - parameter(parameters, at: 0, defaultValue: 1)
            )
            cursorColumn = 0
        case 0x47:
            cursorColumn = min(
                viewport.columns - 1,
                parameter(parameters, at: 0, defaultValue: 1) - 1
            )
        case 0x48, 0x66:
            moveCursor(
                row: parameter(parameters, at: 0, defaultValue: 1),
                column: parameter(parameters, at: 1, defaultValue: 1)
            )
        case 0x4A:
            eraseDisplay(mode: parameters.first ?? 0)
        case 0x4B:
            eraseLine(mode: parameters.first ?? 0)
        case 0x50:
            deleteCharacters(parameter(parameters, at: 0, defaultValue: 1))
        case 0x53:
            let scrollCount = min(
                parameter(parameters, at: 0, defaultValue: 1),
                viewport.rows
            )
            for _ in 0..<scrollCount {
                lineFeed()
            }
        case 0x58:
            eraseCharacters(parameter(parameters, at: 0, defaultValue: 1))
        case 0x64:
            moveCursor(
                row: parameter(parameters, at: 0, defaultValue: 1),
                column: cursorColumn + 1
            )
        case 0x73:
            saveCursor()
        case 0x75:
            restoreCursor()
        case 0x63:
            if rawParameterText.hasPrefix(">") {
                pendingResponse.append(contentsOf: "\u{1B}[>0;0;0c".utf8)
            } else {
                pendingResponse.append(contentsOf: "\u{1B}[?1;2c".utf8)
            }
        case 0x6E:
            respondToDeviceStatus(parameters.first ?? 0)
        case 0x68:
            if isPrivateMode, parameters.contains(where: isAlternateScreenMode) {
                enterAlternateScreen()
            }
        case 0x6C:
            if isPrivateMode, parameters.contains(where: isAlternateScreenMode) {
                leaveAlternateScreen()
            }
        default:
            break
        }
    }

    private mutating func respondToDeviceStatus(_ request: Int) {
        switch request {
        case 5:
            pendingResponse.append(contentsOf: "\u{1B}[0n".utf8)
        case 6:
            let row = max(1, cursorRow - viewportBaseRow + 1)
            let column = max(1, cursorColumn + 1)
            pendingResponse.append(contentsOf: "\u{1B}[\(row);\(column)R".utf8)
        default:
            break
        }
    }

    private func isAlternateScreenMode(_ parameter: Int) -> Bool {
        parameter == 47 || parameter == 1_047 || parameter == 1_049
    }

    private func parameter(
        _ parameters: [Int],
        at index: Int,
        defaultValue: Int
    ) -> Int {
        guard parameters.indices.contains(index), parameters[index] > 0 else {
            return defaultValue
        }
        return parameters[index]
    }

    private var viewportBaseRow: Int {
        max(0, lines.count - viewport.rows)
    }

    private var maximumControlParameter: Int {
        max(maximumLines, maximumColumns)
    }

    private mutating func moveCursor(row: Int, column: Int) {
        cursorRow = viewportBaseRow + min(max(row - 1, 0), viewport.rows - 1)
        cursorColumn = min(max(column - 1, 0), viewport.columns - 1)
        ensureCursorRowExists()
    }

    private mutating func moveCursorDown(_ count: Int) {
        let viewportBottomRow = viewportBaseRow + viewport.rows - 1
        cursorRow = min(cursorRow + count, viewportBottomRow)
        ensureCursorRowExists()
    }

    private mutating func saveCursor() {
        savedCursorRow = cursorRow
        savedCursorColumn = cursorColumn
    }

    private mutating func restoreCursor() {
        cursorRow = min(max(savedCursorRow, 0), lines.count - 1)
        cursorColumn = min(max(savedCursorColumn, 0), viewport.columns - 1)
    }

    private mutating func enterAlternateScreen() {
        guard primaryScreenLines == nil else { return }
        primaryScreenLines = lines
        primaryCursorRow = cursorRow
        primaryCursorColumn = cursorColumn
        lines = [[]]
        cursorRow = 0
        cursorColumn = 0
        savedCursorRow = 0
        savedCursorColumn = 0
    }

    private mutating func leaveAlternateScreen() {
        guard let primaryScreenLines else { return }
        lines = primaryScreenLines
        cursorRow = min(max(primaryCursorRow, 0), lines.count - 1)
        cursorColumn = min(max(primaryCursorColumn, 0), viewport.columns - 1)
        self.primaryScreenLines = nil
    }

    private mutating func writeDecodedUTF8() {
        let decoded = String(decoding: pendingUTF8, as: UTF8.self)
        for character in decoded {
            write(character)
        }
        pendingUTF8.removeAll(keepingCapacity: true)
        expectedUTF8ByteCount = 0
    }

    private mutating func flushIncompleteUTF8() {
        guard expectedUTF8ByteCount > 0 else { return }
        write(Self.replacementCharacter)
        pendingUTF8.removeAll(keepingCapacity: true)
        expectedUTF8ByteCount = 0
    }

    private mutating func write(_ character: Character) {
        if cursorColumn >= min(viewport.columns, maximumColumns) {
            cursorColumn = 0
            lineFeed()
        }
        ensureCursorRowExists()
        while lines[cursorRow].count < cursorColumn {
            lines[cursorRow].append(" ")
        }
        if cursorColumn < lines[cursorRow].count {
            lines[cursorRow][cursorColumn] = character
        } else {
            lines[cursorRow].append(character)
        }
        cursorColumn += 1
    }

    private mutating func tab() {
        let targetColumn = min(((cursorColumn / 8) + 1) * 8, viewport.columns - 1)
        ensureCursorRowExists()
        while lines[cursorRow].count < targetColumn {
            lines[cursorRow].append(" ")
        }
        cursorColumn = targetColumn
    }

    private mutating func lineFeed() {
        cursorRow += 1
        ensureCursorRowExists()
        trimLinesToBounds()
    }

    private mutating func ensureCursorRowExists() {
        while cursorRow >= lines.count {
            lines.append([])
        }
    }

    private mutating func trimLinesToBounds() {
        let overflow = max(0, lines.count - maximumLines)
        guard overflow > 0 else { return }
        lines.removeFirst(overflow)
        cursorRow = max(0, cursorRow - overflow)
        savedCursorRow = max(0, savedCursorRow - overflow)
    }

    private mutating func eraseDisplay(mode: Int) {
        switch mode {
        case 1:
            for row in lines.indices where row < cursorRow {
                lines[row].removeAll(keepingCapacity: true)
            }
            guard lines.indices.contains(cursorRow) else { return }
            let end = min(cursorColumn + 1, lines[cursorRow].count)
            if end > 0 {
                lines[cursorRow].replaceSubrange(0..<end, with: repeatElement(" ", count: end))
            }
        case 2, 3:
            lines = [[]]
            cursorRow = 0
            cursorColumn = 0
        default:
            ensureCursorRowExists()
            if cursorColumn < lines[cursorRow].count {
                lines[cursorRow].removeSubrange(cursorColumn...)
            }
            if cursorRow + 1 < lines.count {
                lines.removeSubrange((cursorRow + 1)...)
            }
        }
    }

    private mutating func eraseLine(mode: Int) {
        ensureCursorRowExists()
        switch mode {
        case 1:
            let end = min(cursorColumn + 1, lines[cursorRow].count)
            if end > 0 {
                lines[cursorRow].replaceSubrange(0..<end, with: repeatElement(" ", count: end))
            }
        case 2:
            lines[cursorRow].removeAll(keepingCapacity: true)
        default:
            if cursorColumn < lines[cursorRow].count {
                lines[cursorRow].removeSubrange(cursorColumn...)
            }
        }
    }

    private mutating func insertBlankCharacters(_ count: Int) {
        ensureCursorRowExists()
        let boundedCount = min(max(count, 0), maximumColumns)
        while lines[cursorRow].count < cursorColumn {
            lines[cursorRow].append(" ")
        }
        lines[cursorRow].insert(
            contentsOf: repeatElement(" ", count: boundedCount),
            at: cursorColumn
        )
        if lines[cursorRow].count > maximumColumns {
            lines[cursorRow].removeLast(lines[cursorRow].count - maximumColumns)
        }
    }

    private mutating func deleteCharacters(_ count: Int) {
        ensureCursorRowExists()
        guard cursorColumn < lines[cursorRow].count else { return }
        let boundedCount = min(max(count, 0), maximumColumns)
        let end = min(cursorColumn + boundedCount, lines[cursorRow].count)
        lines[cursorRow].removeSubrange(cursorColumn..<end)
    }

    private mutating func eraseCharacters(_ count: Int) {
        ensureCursorRowExists()
        let boundedCount = min(max(count, 0), maximumColumns)
        while lines[cursorRow].count < min(cursorColumn + boundedCount, maximumColumns) {
            lines[cursorRow].append(" ")
        }
        let end = min(cursorColumn + boundedCount, lines[cursorRow].count)
        lines[cursorRow].replaceSubrange(
            cursorColumn..<end,
            with: repeatElement(" ", count: end - cursorColumn)
        )
    }
}
