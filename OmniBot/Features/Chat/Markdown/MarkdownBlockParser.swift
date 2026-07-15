import Foundation

nonisolated struct MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        guard !markdown.isEmpty else { return [] }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [MarkdownBlock] = []
        blocks.reserveCapacity(min(lines.count, 64))
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if isBlank(line) {
                lineIndex += 1
                continue
            }

            if let fence = fenceOpening(in: line) {
                let start = lineIndex + 1
                lineIndex = start
                while lineIndex < lines.count,
                      !isFenceClosing(lines[lineIndex], matching: fence) {
                    lineIndex += 1
                }
                let content = join(lines[start..<lineIndex])
                append(
                    .code(language: fence.language, content: content),
                    to: &blocks
                )
                if lineIndex < lines.count { lineIndex += 1 }
                continue
            }

            if let heading = heading(in: line) {
                append(
                    .heading(
                        level: heading.level,
                        content: inlineMarkdown(String(heading.content))
                    ),
                    to: &blocks
                )
                lineIndex += 1
                continue
            }

            if isThematicBreak(line) {
                append(.thematicBreak, to: &blocks)
                lineIndex += 1
                continue
            }

            if let result = table(startingAt: lineIndex, in: lines) {
                append(.table(result.table), to: &blocks)
                lineIndex = result.nextLineIndex
                continue
            }

            if blockQuoteContent(in: line) != nil {
                var quotedLines: [Substring] = []
                while lineIndex < lines.count,
                      let content = blockQuoteContent(in: lines[lineIndex]) {
                    quotedLines.append(content)
                    lineIndex += 1
                }
                append(
                    .quote(inlineMarkdown(join(quotedLines[...]))),
                    to: &blocks
                )
                continue
            }

            if unorderedListContent(in: line) != nil {
                var items: [AttributedString] = []
                while lineIndex < lines.count,
                      let content = unorderedListContent(in: lines[lineIndex]) {
                    items.append(inlineMarkdown(String(content)))
                    lineIndex += 1
                }
                append(.unorderedList(items), to: &blocks)
                continue
            }

            if let firstItem = orderedListContent(in: line) {
                var items = [inlineMarkdown(String(firstItem.content))]
                lineIndex += 1
                while lineIndex < lines.count,
                      let item = orderedListContent(in: lines[lineIndex]) {
                    items.append(inlineMarkdown(String(item.content)))
                    lineIndex += 1
                }
                append(
                    .orderedList(start: firstItem.number, items: items),
                    to: &blocks
                )
                continue
            }

            let paragraphStart = lineIndex
            lineIndex += 1
            while lineIndex < lines.count,
                  !isBlank(lines[lineIndex]),
                  !startsBlock(at: lineIndex, in: lines) {
                lineIndex += 1
            }
            append(
                paragraphKind(join(lines[paragraphStart..<lineIndex])),
                to: &blocks
            )
        }

        return blocks
    }

    private static func append(_ kind: MarkdownBlock.Kind, to blocks: inout [MarkdownBlock]) {
        blocks.append(MarkdownBlock(id: blocks.count, kind: kind))
    }

    private static func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }

    private static func paragraphKind(_ source: String) -> MarkdownBlock.Kind {
        let attributed = inlineMarkdown(source)
        let runs = Array(attributed.runs)
        if runs.count == 1,
           let imageURL = runs[0].imageURL,
           imageURL.scheme?.lowercased() == AgentResourceProtocol.scheme {
            let title = String(attributed.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .resourceImage(
                title: title.isEmpty ? "Image" : title,
                url: imageURL
            )
        }
        return .paragraph(attributed)
    }

    private static func startsBlock(at index: Int, in lines: [Substring]) -> Bool {
        let line = lines[index]
        return fenceOpening(in: line) != nil
            || heading(in: line) != nil
            || isThematicBreak(line)
            || isTableOpening(at: index, in: lines)
            || blockQuoteContent(in: line) != nil
            || unorderedListContent(in: line) != nil
            || orderedListContent(in: line) != nil
    }

    private static func table(
        startingAt index: Int,
        in lines: [Substring]
    ) -> (table: MarkdownTable, nextLineIndex: Int)? {
        guard index + 1 < lines.count,
              let headerCells = tableCells(in: lines[index]),
              let delimiterCells = tableCells(in: lines[index + 1]),
              !headerCells.isEmpty,
              headerCells.count == delimiterCells.count else {
            return nil
        }

        let alignments = delimiterCells.compactMap(tableAlignment)
        guard alignments.count == delimiterCells.count else { return nil }

        let header = headerCells.map(inlineMarkdown)
        var rows: [[AttributedString]] = []
        var nextLineIndex = index + 2
        while nextLineIndex < lines.count,
              !isBlank(lines[nextLineIndex]),
              let cells = tableCells(in: lines[nextLineIndex]) {
            rows.append(normalizedTableRow(cells, columnCount: header.count))
            nextLineIndex += 1
        }

        return (
            MarkdownTable(header: header, rows: rows, alignments: alignments),
            nextLineIndex
        )
    }

    private static func isTableOpening(at index: Int, in lines: [Substring]) -> Bool {
        guard index + 1 < lines.count,
              let headerCells = tableCells(in: lines[index]),
              let delimiterCells = tableCells(in: lines[index + 1]),
              !headerCells.isEmpty,
              headerCells.count == delimiterCells.count else {
            return false
        }
        return delimiterCells.allSatisfy { tableAlignment($0) != nil }
    }

    private static func tableCells(in line: Substring) -> [String]? {
        var content = trimmedWhitespace(line)
        guard content.contains("|") else { return nil }
        if content.first == "|" { content = content.dropFirst() }
        if content.last == "|" { content = content.dropLast() }

        var cells: [String] = []
        var current = String()
        var isEscaped = false
        var isInsideCode = false

        for character in content {
            if isEscaped {
                if character != "|" { current.append("\\") }
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "`" {
                isInsideCode.toggle()
                current.append(character)
            } else if character == "|", !isInsideCode {
                cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }
        }
        if isEscaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return cells
    }

    private static func tableAlignment(
        _ delimiter: String
    ) -> MarkdownTable.ColumnAlignment? {
        var marker = delimiter.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLeadingColon = marker.first == ":"
        let hasTrailingColon = marker.last == ":"
        if hasLeadingColon { marker.removeFirst() }
        if hasTrailingColon, !marker.isEmpty { marker.removeLast() }
        guard marker.count >= 3, marker.allSatisfy({ $0 == "-" }) else { return nil }

        if hasLeadingColon && hasTrailingColon { return .center }
        if hasTrailingColon { return .trailing }
        return .leading
    }

    private static func normalizedTableRow(
        _ cells: [String],
        columnCount: Int
    ) -> [AttributedString] {
        (0..<columnCount).map { column in
            guard column < cells.count else { return AttributedString() }
            return inlineMarkdown(cells[column])
        }
    }

    private static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    private static func trimmedLeadingWhitespace(_ line: Substring) -> Substring {
        line.drop(while: \.isWhitespace)
    }

    private static func trimmedWhitespace(_ value: Substring) -> Substring {
        var trimmed = value.drop(while: \.isWhitespace)
        while trimmed.last?.isWhitespace == true {
            trimmed = trimmed.dropLast()
        }
        return trimmed
    }

    private static func join(_ lines: ArraySlice<Substring>) -> String {
        guard let first = lines.first else { return "" }

        let contentBytes = lines.reduce(0) { $0 + $1.utf8.count }
        var result = String()
        result.reserveCapacity(contentBytes + max(0, lines.count - 1))
        result.append(contentsOf: first)
        for line in lines.dropFirst() {
            result.append("\n")
            result.append(contentsOf: line)
        }
        return result
    }

    private static func fenceOpening(
        in line: Substring
    ) -> (character: Character, length: Int, language: String?)? {
        let trimmed = trimmedLeadingWhitespace(line)
        guard let character = trimmed.first, character == "`" || character == "~" else {
            return nil
        }
        let length = trimmed.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        let info = trimmedWhitespace(trimmed.dropFirst(length))
        let language = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return (character, length, language)
    }

    private static func isFenceClosing(
        _ line: Substring,
        matching fence: (character: Character, length: Int, language: String?)
    ) -> Bool {
        let trimmed = trimmedLeadingWhitespace(line)
        let length = trimmed.prefix(while: { $0 == fence.character }).count
        guard length >= fence.length else { return false }
        return trimmed.dropFirst(length).allSatisfy(\.isWhitespace)
    }

    private static func heading(in line: Substring) -> (level: Int, content: Substring)? {
        let trimmed = trimmedLeadingWhitespace(line)
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let remainder = trimmed.dropFirst(level)
        guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }
        return (level, remainder.drop(while: \.isWhitespace))
    }

    private static func isThematicBreak(_ line: Substring) -> Bool {
        let visible = trimmedWhitespace(line).filter { !$0.isWhitespace }
        guard visible.count >= 3, let marker = visible.first,
              marker == "-" || marker == "*" || marker == "_" else {
            return false
        }
        return visible.allSatisfy { $0 == marker }
    }

    private static func blockQuoteContent(in line: Substring) -> Substring? {
        let trimmed = trimmedLeadingWhitespace(line)
        guard trimmed.first == ">" else { return nil }
        return trimmed.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
    }

    private static func unorderedListContent(in line: Substring) -> Substring? {
        let trimmed = trimmedLeadingWhitespace(line)
        guard let marker = trimmed.first,
              marker == "-" || marker == "*" || marker == "+" else {
            return nil
        }
        let remainder = trimmed.dropFirst()
        guard remainder.first?.isWhitespace == true else { return nil }
        return remainder.drop(while: \.isWhitespace)
    }

    private static func orderedListContent(
        in line: Substring
    ) -> (number: Int, content: Substring)? {
        let trimmed = trimmedLeadingWhitespace(line)
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty,
              let number = Int(digits),
              let punctuation = trimmed.dropFirst(digits.count).first,
              punctuation == "." || punctuation == ")" else {
            return nil
        }
        let remainder = trimmed.dropFirst(digits.count + 1)
        guard remainder.first?.isWhitespace == true else { return nil }
        return (number, remainder.drop(while: \.isWhitespace))
    }
}
