import SwiftUI

struct ProviderProfileRow: View {
    let profile: ProviderProfile

    var body: some View {
        HStack(spacing: AppDesign.standardSpacing) {
            Image(systemName: "server.rack")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .foregroundStyle(.primary)
                Text(profile.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppDesign.compactSpacing)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .contentShape(.rect)
    }
}
