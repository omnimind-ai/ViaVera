import SwiftUI

struct ModelUsagePanel<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
            VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppDesign.contentPadding)
        .background(.background, in: .rect(cornerRadius: ModelUsageStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ModelUsageStyle.cornerRadius)
                .strokeBorder(.primary.opacity(0.045), lineWidth: 1)
                .accessibilityHidden(true)
        }
    }
}
