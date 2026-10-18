import Foundation
import SwiftUI
import Testing
@testable import Via_Vera

@Suite("Transcript scroll ownership")
@MainActor
struct TranscriptScrollStateTests {
    @Test("Streaming never takes the viewport during a gesture or momentum")
    func manualScrollingSuspendsFollowing() {
        let state = TranscriptScrollState()
        #expect(state.canFollow())
        for phase: ScrollPhase in [.tracking, .interacting, .decelerating] {
            state.updatePhase(phase, isNearBottom: true)
            #expect(!state.canFollow())
        }
        state.updatePhase(.idle, isNearBottom: true)
        #expect(state.canFollow())
    }

    @Test("Idle layout changes cannot re-pin a reader browsing history")
    func layoutChangesDoNotStealReadingPosition() {
        let state = TranscriptScrollState()
        state.updatePhase(.interacting, isNearBottom: true)
        state.updateNearBottom(false)
        state.updatePhase(.decelerating, isNearBottom: false)
        state.updatePhase(.idle, isNearBottom: false)
        state.updateNearBottom(true)
        #expect(!state.canFollow())

        state.updatePhase(.interacting, isNearBottom: false)
        state.updateNearBottom(true)
        state.updatePhase(.idle, isNearBottom: true)
        #expect(state.canFollow())
    }

    @Test("Content growth and programmatic positioning preserve follow intent")
    func layoutGrowthDoesNotUnpin() {
        let state = TranscriptScrollState()
        state.updateNearBottom(false)
        #expect(state.canFollow())
        state.updatePhase(.animating, isNearBottom: false)
        state.updateNearBottom(false)
        #expect(!state.canFollow())
        state.updatePhase(.idle, isNearBottom: false)
        #expect(state.canFollow())
    }

    @Test("Disclosure suppression expires and explicit sends resume following")
    func suppressionAndResume() {
        let state = TranscriptScrollState()
        let now = Date(timeIntervalSince1970: 1_000)
        state.suppressFollowing(until: now.addingTimeInterval(0.42))
        #expect(!state.canFollow(at: now))
        #expect(state.canFollow(at: now.addingTimeInterval(0.43)))

        state.updatePhase(.interacting, isNearBottom: false)
        state.updatePhase(.idle, isNearBottom: false)
        state.suppressFollowing(until: now.addingTimeInterval(10))
        state.resumeFollowing()
        #expect(state.canFollow(at: now))

        state.updatePhase(.decelerating, isNearBottom: false)
        state.reset()
        #expect(state.canFollow(at: now))
    }
}
