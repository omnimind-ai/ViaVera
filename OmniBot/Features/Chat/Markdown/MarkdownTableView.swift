import SwiftUI

struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.header.indices, id: \.self) { column in
                        MarkdownTableCellView(
                            content: table.header[column],
                            alignment: table.alignments[column],
                            isHeader: true
                        )
                    }
                }

                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.header.indices, id: \.self) { column in
                            MarkdownTableCellView(
                                content: table.rows[row][column],
                                alignment: table.alignments[column],
                                isHeader: false
                            )
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.28), lineWidth: 0.5)
                    .accessibilityHidden(true)
            }
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown 表格")
    }
}
