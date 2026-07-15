#if os(macOS)
import SwiftUI

struct MacChatScrollTopFadeMask: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.12), location: 0.28),
                    .init(color: .black.opacity(0.58), location: 0.68),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: AppDesign.macChatScrollTopFadeHeight)

            Rectangle()
                .fill(.black)
        }
        .accessibilityHidden(true)
    }
}
#endif
