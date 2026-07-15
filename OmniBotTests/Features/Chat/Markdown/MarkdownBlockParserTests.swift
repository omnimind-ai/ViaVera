import Foundation
import Testing
@testable import Via_Vera

@Suite("Chat Markdown parser")
struct MarkdownBlockParserTests {
    @Test("A standalone Omnibot image artifact becomes a resource image block")
    func parsesResourceImage() throws {
        let blocks = MarkdownBlockParser.parse(
            "![Browser capture](omnibot://browser/run/capture.png)"
        )

        let block = try #require(blocks.first)
        guard case let .resourceImage(title, url) = block.kind else {
            Issue.record("Expected a resource image block")
            return
        }
        #expect(title == "Browser capture")
        #expect(url.absoluteString == "omnibot://browser/run/capture.png")
    }

    @Test("Parses common streaming chat Markdown blocks")
    func parsesCommonBlocks() throws {
        let blocks = MarkdownBlockParser.parse(
            """
            # Title

            A **bold** paragraph with [a link](https://example.com).

            > Quoted *text*

            - One
            - Two

            3. Three
            4. Four

            ```swift
            let answer = 42
            ```

            ---
            """
        )

        #expect(blocks.count == 7)
        #expect(blocks[0].kind == .heading(level: 1, content: try inline("Title")))
        #expect(blocks[2].kind == .quote(try inline("Quoted *text*")))
        #expect(
            blocks[5].kind == .code(language: "swift", content: "let answer = 42")
        )
        #expect(blocks[6].kind == .thematicBreak)
    }

    @Test("Keeps an unfinished fenced block renderable during streaming")
    func parsesUnfinishedFence() {
        let blocks = MarkdownBlockParser.parse(
            """
            Before

            ```json
            {"ready": false}
            """
        )

        #expect(blocks.count == 2)
        #expect(
            blocks[1].kind == .code(language: "json", content: "{\"ready\": false}")
        )
    }

    @Test("Falls back to plain text for incomplete inline syntax")
    func parsesIncompleteInlineSyntax() {
        let blocks = MarkdownBlockParser.parse("Streaming **bold")

        #expect(blocks.count == 1)
        guard case let .paragraph(content) = blocks[0].kind else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(String(content.characters) == "Streaming **bold")
    }

    @Test("Parses GFM tables with alignment and inline Markdown")
    func parsesTable() {
        let blocks = MarkdownBlockParser.parse(
            """
            | 项目 | 值 |
            | :--- | ---: |
            | **操作系统** | Alpine Linux v3.21 |
            | 主机名 | ocean\\|MacBook |

            After table
            """
        )

        #expect(blocks.count == 2)
        guard case let .table(table) = blocks[0].kind else {
            Issue.record("Expected a table")
            return
        }
        #expect(table.header.map { String($0.characters) } == ["项目", "值"])
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.rows.count == 2)
        #expect(String(table.rows[0][0].characters) == "操作系统")
        #expect(String(table.rows[1][1].characters) == "ocean|MacBook")
    }

    private func inline(_ source: String) throws -> AttributedString {
        try AttributedString(
            markdown: source,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
    }
}
