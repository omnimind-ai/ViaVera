import SwiftUI

struct AgentTurnProcessRevealView: View {
    let messages: [ChatMessagePresentation]
    let isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AgentTurnRevealLayout(progress: isExpanded ? 1 : 0) {
            AgentTurnProcessMessagesView(messages: messages)
                .padding(.top, AppDesign.compactSpacing)
        }
            .clipped()
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.26),
                value: isExpanded
            )
    }
}
