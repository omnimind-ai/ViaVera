import SwiftUI

struct ComposerIconLabel: View {
    let title: String
    let assetName: String
    let size: CGFloat

    var body: some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .fixedSize()
            .accessibilityLabel(title)
    }
}
