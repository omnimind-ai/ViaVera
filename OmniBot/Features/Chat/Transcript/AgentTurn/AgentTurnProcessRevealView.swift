import SwiftUI

struct AgentTurnProcessRevealView: View {
    let messages: [ChatMessagePresentation]
    let isExpanded: Bool

    var body: some View {
        TranscriptDisclosureView(isExpanded: isExpanded, duration: 0.26) {
            AgentTurnProcessMessagesView(messages: messages)
                .padding(.top, AppDesign.compactSpacing)
        }
    }
}
