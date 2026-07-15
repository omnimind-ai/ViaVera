import SwiftUI

struct ComposerGlassEdge: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        RoundedRectangle(cornerRadius: AppDesign.composerCornerRadius)
            .strokeBorder(
                Color.primary.opacity(neutralEdgeOpacity),
                lineWidth: neutralEdgeWidth
            )
            .accessibilityHidden(true)
    }

    private var neutralEdgeOpacity: Double {
        colorSchemeContrast == .increased ? 0.32 : 0.12
    }

    private var neutralEdgeWidth: Double {
        colorSchemeContrast == .increased ? 1.25 : 0.75
    }
}
