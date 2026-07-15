import SwiftUI

struct ShimmeringText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.primary.opacity(0.62),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(proxy.size.width * 0.7, 1))
                    .offset(x: phase * proxy.size.width)
                }
                .mask {
                    Text(text)
                }
                .accessibilityHidden(true)
            }
            .clipped()
            .task(id: reduceMotion) {
                phase = -1
                guard !reduceMotion else { return }
                await Task.yield()
                withAnimation(
                    .linear(duration: 1.35)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}
