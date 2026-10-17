import SwiftUI

/// Hover changes visibility only, so inspecting a reply never moves its text
/// or scroll position. Touch devices expose the same details in a popover.
struct ResponseDetailsModifier: ViewModifier {
    let completion: ResponseCompletionPresentation?

#if os(macOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isHovering = false
#else
    @State private var showsDetails = false
#endif

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            content
            if let completion {
#if os(macOS)
                MessageResponseDetailsView(completion: completion)
                    .opacity(isHovering || voiceOverEnabled ? 1 : 0)
                    .allowsHitTesting(isHovering || voiceOverEnabled)
                    .accessibilityHidden(!isHovering && !voiceOverEnabled)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
#else
                Button(action: showDetails) {
                    Label("回复信息", systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showsDetails) {
                        MessageResponseDetailsView(completion: completion)
                            .padding()
                            .presentationCompactAdaptation(.popover)
                    }
#endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
#if os(macOS)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
#endif
    }

#if !os(macOS)
    private func showDetails() { showsDetails = true }
#endif
}
