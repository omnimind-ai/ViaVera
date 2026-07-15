import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent turn expansion state")
struct AgentTurnExpansionStateTests {
    @Test("Most recently expanded completed turn drives pinned tool activity")
    @MainActor
    func expansionOrderSelectsPreferredCompletedTurn() {
        let firstID = UUID()
        let secondID = UUID()
        let first = AgentTurnPresentation(
            id: firstID,
            processMessages: [],
            visibleMessages: [],
            isActive: false
        )
        let second = AgentTurnPresentation(
            id: secondID,
            processMessages: [],
            visibleMessages: [],
            isActive: false
        )
        var state = AgentTurnExpansionState()

        state.toggle(firstID)
        state.toggle(secondID)
        #expect(state.preferredCompletedTurnID(in: [first, second]) == secondID)

        state.collapse(secondID)
        #expect(state.preferredCompletedTurnID(in: [first, second]) == firstID)

        state.toggle(firstID)
        #expect(state.preferredCompletedTurnID(in: [first, second]) == nil)
    }

    @Test("Active turns never become pinned completed activity")
    @MainActor
    func activeTurnIsExcludedFromPreferredCompletedTurn() {
        let turnID = UUID()
        let active = AgentTurnPresentation(
            id: turnID,
            processMessages: [],
            visibleMessages: [],
            isActive: true
        )
        var state = AgentTurnExpansionState()

        state.toggle(turnID)

        #expect(state.preferredCompletedTurnID(in: [active]) == nil)
    }

    @Test("Starting a new user turn clears completed pins")
    @MainActor
    func newUserTurnClearsCompletedPins() {
        let turnID = UUID()
        let completed = AgentTurnPresentation(
            id: turnID,
            processMessages: [],
            visibleMessages: [],
            isActive: false
        )
        var state = AgentTurnExpansionState()
        state.toggle(turnID)

        state.reset()

        #expect(state.preferredCompletedTurnID(in: [completed]) == nil)
        #expect(state.manuallyExpandedTurnIDs.isEmpty)
        #expect(state.expansionOrder.isEmpty)
    }
}
