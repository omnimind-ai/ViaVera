#if os(macOS)
import SwiftUI

struct MacChatMoreMenu: View {
    let conversationID: UUID
    @Binding var isPresentingBrowser: Bool
    let openBrowser: () -> Void
    let openWorkspace: () -> Void
    let openSettings: () -> Void
    let dismissComposerFocus: () -> Void

    var body: some View {
        ChatMoreMenu(
            openBrowser: openBrowser,
            openWorkspace: openWorkspace,
            openSettings: openSettings
        )
        .popover(isPresented: $isPresentingBrowser, arrowEdge: .top) {
            BrowserCardView(conversationID: conversationID)
        }
        .simultaneousGesture(
            TapGesture().onEnded(dismissComposerFocus)
        )
    }
}
#endif
