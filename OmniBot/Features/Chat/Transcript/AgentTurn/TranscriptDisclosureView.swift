import SwiftUI

/// Keep content alive only for an open disclosure and its closing animation.
/// Folded historical tool calls must not build, parse, or measure hidden views.
struct TranscriptDisclosureView<Content: View>: View {
    let isExpanded: Bool
    let duration: TimeInterval
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: TranscriptDisclosureState

    init(isExpanded: Bool, duration: TimeInterval, @ViewBuilder content: () -> Content) {
        self.isExpanded = isExpanded
        self.duration = duration
        self.content = content()
        _reveal = State(initialValue: TranscriptDisclosureState(isExpanded: isExpanded))
    }

    var body: some View {
        AgentTurnRevealLayout(progress: reveal.progress) {
            if reveal.isMounted {
                content.transition(.identity)
            }
        }
        .clipped()
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            var next = reveal
            next.setExpanded(expanded)
            let revision = next.revision
            withTransaction(\.scrollContentOffsetAdjustmentBehavior, .disabled) {
                withAnimation(
                    reduceMotion ? nil : .easeInOut(duration: duration),
                    completionCriteria: .removed
                ) {
                    reveal = next
                } completion: {
                    reveal.finishCollapse(revision: revision)
                }
            }
        }
    }
}
