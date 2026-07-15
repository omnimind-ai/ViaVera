import SwiftUI

struct MarkdownContentView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block)
            }
        }
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
