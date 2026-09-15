import Foundation
import Testing
@testable import Via_Vera

@Suite("Chat composer skill references")
@MainActor
struct ChatComposerDraftTests {
    @Test("A skill reference waits for a user request and is included in the outgoing message")
    func referencedRequest() throws {
        let draft = ChatComposerDraft()
        draft.skillReference = .nativeToolBuilder()
        #expect(draft.text.isEmpty)
        #expect(draft.messageToSend == nil)
        draft.text = " \n "
        #expect(draft.messageToSend == nil)
        draft.text = "做一个待办清单"
        let message = try #require(draft.messageToSend)
        #expect(message.contains("$native-tool-builder"))
        #expect(message.hasSuffix(draft.text))
        #expect(draft.text == "做一个待办清单")
        draft.clearAfterSending()
        #expect(draft.messageToSend == nil)
        #expect(draft.skillReference == nil)
        draft.text = "下一条普通消息"
        #expect(draft.messageToSend == draft.text)
    }

    @Test("Removing the capsule preserves the user's text and removes its invocation and edit context")
    func removeReference() {
        let draft = ChatComposerDraft()
        draft.skillReference = .nativeToolBuilder(editing: UUID())
        draft.text = "改为深色主题"
        draft.skillReference = nil
        #expect(draft.text == "改为深色主题")
        #expect(draft.messageToSend == draft.text)
    }

    @Test("Editing a tool carries its identity without leaking into another conversation draft")
    func editingContext() throws {
        let toolID = UUID()
        let toolDraft = ChatComposerDraft()
        toolDraft.skillReference = .nativeToolBuilder(editing: toolID)
        toolDraft.text = "增加一个重置按钮"
        let message = try #require(toolDraft.messageToSend)
        #expect(message.contains(toolID.uuidString))
        #expect(message.contains("先读取最新工具包及 revision"))
        let ordinaryDraft = ChatComposerDraft()
        ordinaryDraft.text = "帮我总结文档"
        #expect(ordinaryDraft.skillReference == nil)
        #expect(ordinaryDraft.messageToSend == ordinaryDraft.text)
        #expect(toolDraft.skillReference?.id == "native-tool-builder")
    }
}
