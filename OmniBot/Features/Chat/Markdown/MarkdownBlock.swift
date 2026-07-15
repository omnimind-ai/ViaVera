import Foundation

nonisolated struct MarkdownBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph(AttributedString)
        case heading(level: Int, content: AttributedString)
        case code(language: String?, content: String)
        case quote(AttributedString)
        case unorderedList([AttributedString])
        case orderedList(start: Int, items: [AttributedString])
        case table(MarkdownTable)
        case resourceImage(title: String, url: URL)
        case thematicBreak
    }

    let id: Int
    let kind: Kind
}
