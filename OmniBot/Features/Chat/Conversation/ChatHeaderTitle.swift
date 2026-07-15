import SwiftUI

struct ChatHeaderTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}
