import Foundation

/// Keeps answer text responsive while limiting cumulative reasoning rewrites.
/// Reasoning-only snapshots are emitted immediately for the first frame, then
/// at most once per interval. Before answer text advances, any pending reasoning
/// is emitted first so coalescing cannot make both fields grow in one update.
/// Callers must flush before completing a stream.
actor AgentStreamSnapshotCoalescer {
    typealias Handler = @Sendable (AgentStreamSnapshot) async throws -> Void

    private let minimumReasoningInterval: Duration
    private let clock = ContinuousClock()
    private let handler: Handler
    private var lastEmittedSnapshot = AgentStreamSnapshot()
    private var lastEmission: ContinuousClock.Instant?
    private var pendingSnapshot: AgentStreamSnapshot?

    init(
        minimumReasoningInterval: Duration = .milliseconds(300),
        handler: @escaping Handler
    ) {
        self.minimumReasoningInterval = minimumReasoningInterval
        self.handler = handler
    }

    func consume(_ snapshot: AgentStreamSnapshot) async throws {
        guard snapshot != lastEmittedSnapshot,
              snapshot != pendingSnapshot else { return }

        if shouldEmitImmediately(snapshot) {
            if snapshot.content != lastEmittedSnapshot.content {
                try await emitPendingSnapshot()
            } else {
                pendingSnapshot = nil
            }
            try await emitSeparatingFieldChanges(snapshot)
        } else {
            pendingSnapshot = snapshot
        }
    }

    func flush() async throws {
        try await emitPendingSnapshot()
    }

    private func shouldEmitImmediately(_ snapshot: AgentStreamSnapshot) -> Bool {
        guard let lastEmission else { return true }
        if snapshot.content != lastEmittedSnapshot.content {
            return true
        }
        return lastEmission.duration(to: clock.now) >= minimumReasoningInterval
    }

    private func emit(_ snapshot: AgentStreamSnapshot) async throws {
        try await handler(snapshot)
        lastEmittedSnapshot = snapshot
        lastEmission = clock.now
    }

    private func emitPendingSnapshot() async throws {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        try await emitSeparatingFieldChanges(pendingSnapshot)
    }

    /// Provider snapshots are cumulative, so both fields may be non-empty. If
    /// one provider event advances both fields, preserve that cumulative shape
    /// while inserting a reasoning boundary before the answer update.
    private func emitSeparatingFieldChanges(_ snapshot: AgentStreamSnapshot) async throws {
        guard snapshot != lastEmittedSnapshot else { return }
        let contentChanged = snapshot.content != lastEmittedSnapshot.content
        let reasoningChanged = snapshot.reasoningContent
            != lastEmittedSnapshot.reasoningContent

        if contentChanged, reasoningChanged {
            try await emit(AgentStreamSnapshot(
                content: lastEmittedSnapshot.content,
                reasoningContent: snapshot.reasoningContent
            ))
        }
        if snapshot != lastEmittedSnapshot {
            try await emit(snapshot)
        }
    }
}
