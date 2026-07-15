import SwiftUI

struct ComposerControlFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                width: AppDesign.composerControlSize,
                height: AppDesign.composerControlSize
            )
            .contentShape(.circle)
    }
}

extension View {
    func composerControlFrame() -> some View {
        modifier(ComposerControlFrameModifier())
    }
}
