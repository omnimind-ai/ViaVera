import SwiftUI

struct MarkdownTableCellView: View {
    let content: AttributedString
    let alignment: MarkdownTable.ColumnAlignment
    let isHeader: Bool

    var body: some View {
        Text(content)
            .font(isHeader ? .headline : .body)
            .multilineTextAlignment(textAlignment)
            .lineLimit(nil)
            .fixedSize(horizontal: true, vertical: true)
            .frame(
                minWidth: 96,
                minHeight: 28,
                alignment: frameAlignment
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: frameAlignment
            )
            .background(isHeader ? Color.secondary.opacity(0.08) : Color.clear)
            .overlay {
                Rectangle()
                    .stroke(.secondary.opacity(0.22), lineWidth: 0.5)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
