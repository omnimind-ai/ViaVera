import SwiftUI

/// Scroll bookkeeping is deliberately not observable: wheel events must not
/// invalidate the conversation, decode its history, or rebuild the composer.
@MainActor
final class TranscriptScrollState {
    private(set) var followsLatest = true
    private(set) var phase: ScrollPhase = .idle
    private var suppressedUntil: Date?

    func canFollow(at date: Date = .now) -> Bool {
        followsLatest && phase == .idle && (suppressedUntil.map { date >= $0 } ?? true)
    }

    func updatePhase(_ newPhase: ScrollPhase, isNearBottom: Bool) {
        let wasUserScrolling = isUserScrolling
        phase = newPhase
        if isUserScrolling || (newPhase == .idle && wasUserScrolling) {
            followsLatest = isNearBottom
        }
    }

    func updateNearBottom(_ isNearBottom: Bool) {
        // Lazy row measurement, image loading, and programmatic positioning
        // can change geometry while idle. They are not a request to re-pin.
        if isUserScrolling { followsLatest = isNearBottom }
    }

    func resumeFollowing() {
        followsLatest = true
        suppressedUntil = nil
    }

    func suppressFollowing(until date: Date) { suppressedUntil = date }

    func reset() {
        followsLatest = true
        phase = .idle
        suppressedUntil = nil
    }

    private var isUserScrolling: Bool {
        phase == .tracking || phase == .interacting || phase == .decelerating
    }
}
