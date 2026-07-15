import SwiftUI

struct SettingsCardRow: View {
    let destination: SettingsCardDestination

    var body: some View {
        Label {
            Text(destination.title)
                .lineLimit(1)
        } icon: {
            Image(systemName: destination.systemImage)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(.rect)
        .accessibilityHint(destination.subtitle)
    }
}
