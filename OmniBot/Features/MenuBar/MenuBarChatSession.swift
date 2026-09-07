#if os(macOS)
import Observation

@MainActor
@Observable
final class MenuBarChatSession {
    var isPinned = true
    let composerDraft = ChatComposerDraft()
}
#endif
