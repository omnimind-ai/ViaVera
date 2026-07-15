import Foundation

nonisolated struct MarkdownTable: Equatable, Sendable {
    enum ColumnAlignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    let header: [AttributedString]
    let rows: [[AttributedString]]
    let alignments: [ColumnAlignment]
}
