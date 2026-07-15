import SwiftUI

struct MarkdownCodeBlockView: View {
    let language: String?
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("代码语言：\(language)")
            }

            ScrollView(.horizontal) {
                Text(verbatim: content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(AppDesign.compactSpacing)
            }
        }
        .padding(AppDesign.compactSpacing)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
