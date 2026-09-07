import Foundation
import Observation

@MainActor
@Observable
final class ChatComposerDraft {
    var text = ""
    var editingUserMessageID: UUID?
}
