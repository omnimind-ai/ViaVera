import SwiftUI

struct ChatActivitySurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let surfaceShape = UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 18
        )

        content
            .fixedSize(horizontal: false, vertical: true)
            .background(.thinMaterial, in: surfaceShape)
            .overlay {
                surfaceShape
                    .strokeBorder(Color.primary.opacity(0.07))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
    }
}
