import SwiftUI

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block.kind {
        case let .paragraph(content):
            Text(content)
                .font(.body)

        case let .heading(level, content):
            Text(content)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

        case let .code(language, content):
            MarkdownCodeBlockView(language: language, content: content)

        case let .quote(content):
            HStack(alignment: .top, spacing: AppDesign.compactSpacing) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.secondary.opacity(0.55))
                    .frame(width: 3)
                    .accessibilityHidden(true)
                Text(content)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: AppDesign.compactSpacing) {
                        Text("•")
                            .accessibilityHidden(true)
                        Text(items[index])
                            .font(.body)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("列表项：\(String(items[index].characters))")
                }
            }

        case let .orderedList(start, items):
            VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: AppDesign.compactSpacing) {
                        Text("\(start + index).")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(items[index])
                            .font(.body)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "第 \(start + index) 项：\(String(items[index].characters))"
                    )
                }
            }

        case let .table(table):
            MarkdownTableView(table: table)

        case let .resourceImage(title, url):
            AgentResourceImageView(title: title, resourceURL: url)

        case .thematicBreak:
            Divider()
                .accessibilityHidden(true)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        case 3: .headline
        default: .subheadline
        }
    }
}
