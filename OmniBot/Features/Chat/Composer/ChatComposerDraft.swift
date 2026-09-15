import Foundation
import Observation

@MainActor
@Observable
final class ChatComposerDraft {
    var text = ""
    var editingUserMessageID: UUID?
    var skillReference: ChatComposerSkillReference?
    var requestsFocus = false

    var messageToSend: String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return skillReference?.message(including: text) ?? text
    }

    func clearAfterSending() {
        text = ""
        skillReference = nil
        requestsFocus = false
    }
}
