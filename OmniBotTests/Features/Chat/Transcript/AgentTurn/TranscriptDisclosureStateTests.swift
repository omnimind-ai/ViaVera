import Testing
@testable import Via_Vera

@Suite("Transcript disclosure lifetime")
@MainActor
struct TranscriptDisclosureStateTests {
    @Test("Collapsed history has no mounted process content")
    func collapsedHistoryIsUnmounted() {
        let state = TranscriptDisclosureState(isExpanded: false)
        #expect(!state.isMounted)
        #expect(state.progress == 0)
    }

    @Test("Closing preserves content until the reveal animation finishes")
    func closeRetainsContentUntilCompletion() {
        var state = TranscriptDisclosureState(isExpanded: true)
        state.setExpanded(false)
        #expect(state.isMounted)
        #expect(state.progress == 0)
        state.finishCollapse(revision: state.revision)
        #expect(!state.isMounted)
    }

    @Test("A stale animation completion cannot remove reopened content")
    func interruptedCollapseDoesNotRemoveReopenedContent() {
        var state = TranscriptDisclosureState(isExpanded: true)
        state.setExpanded(false)
        let firstClose = state.revision
        state.setExpanded(true)
        state.finishCollapse(revision: firstClose)
        #expect(state.isMounted)
        #expect(state.progress == 1)

        state.setExpanded(false)
        state.finishCollapse(revision: firstClose)
        #expect(state.isMounted)
        state.finishCollapse(revision: state.revision)
        #expect(!state.isMounted)
    }
}
