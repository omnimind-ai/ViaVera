import Foundation
import Observation

@MainActor
@Observable
final class ChatToolActivityModel {
    private static let maximumOutputCharacters = 12_000
    private static let truncationMarker = "\n…更早的终端输出已省略\n"
    private static let outputPublishInterval = Duration.milliseconds(70)

    private(set) var snapshot: ChatToolLiveSnapshot?

    @ObservationIgnored
    private var mostRecentAssistantMessageID: UUID?

    @ObservationIgnored
    private var accumulatedTerminalOutput = ""

    @ObservationIgnored
    private var outputFlushTask: Task<Void, Never>?

    func beginRun(runID: UUID, conversationID: UUID) {
        resetOutputBuffer()
        mostRecentAssistantMessageID = nil
        snapshot = ChatToolLiveSnapshot(
            runID: runID,
            conversationID: conversationID,
            assistantMessageIDs: [],
            activeAssistantMessageID: nil,
            activeCallID: nil,
            terminalOutput: ""
        )
    }

    func registerAssistantMessage(id: UUID, runID: UUID) {
        guard let snapshot, snapshot.runID == runID else { return }
        mostRecentAssistantMessageID = id
        guard !snapshot.assistantMessageIDs.contains(id) else { return }

        var assistantMessageIDs = snapshot.assistantMessageIDs
        assistantMessageIDs.insert(id)
        self.snapshot = ChatToolLiveSnapshot(
            runID: snapshot.runID,
            conversationID: snapshot.conversationID,
            assistantMessageIDs: assistantMessageIDs,
            activeAssistantMessageID: snapshot.activeAssistantMessageID,
            activeCallID: snapshot.activeCallID,
            terminalOutput: snapshot.terminalOutput
        )
    }

    func beginTool(_ call: AgentToolCall, runID: UUID) {
        guard let snapshot,
              snapshot.runID == runID,
              let assistantMessageID = mostRecentAssistantMessageID,
              snapshot.assistantMessageIDs.contains(assistantMessageID) else {
            return
        }
        resetOutputBuffer()
        self.snapshot = ChatToolLiveSnapshot(
            runID: snapshot.runID,
            conversationID: snapshot.conversationID,
            assistantMessageIDs: snapshot.assistantMessageIDs,
            activeAssistantMessageID: assistantMessageID,
            activeCallID: call.id,
            terminalOutput: ""
        )
    }

    func appendTerminalOutput(
        _ fragment: String,
        isStandardError: Bool,
        runID: UUID,
        callID: String
    ) {
        guard let snapshot,
              snapshot.runID == runID,
              snapshot.activeAssistantMessageID != nil,
              snapshot.activeCallID == callID,
              !fragment.isEmpty else {
            return
        }
        let normalizedFragment: String
        if isStandardError {
            normalizedFragment = fragment.hasSuffix("\n")
                ? "stderr: \(fragment)"
                : "stderr: \(fragment)\n"
        } else {
            normalizedFragment = fragment.hasSuffix("\n") ? fragment : "\(fragment)\n"
        }
        let combined = accumulatedTerminalOutput + normalizedFragment
        if combined.count <= Self.maximumOutputCharacters {
            accumulatedTerminalOutput = combined
        } else {
            accumulatedTerminalOutput = Self.truncationMarker
                + String(combined.suffix(Self.maximumOutputCharacters))
        }
        scheduleOutputFlush(runID: runID, callID: callID)
    }

    /// Coalesces terminal callbacks so a high-volume command does not force a
    /// complete transcript presentation rebuild for every emitted line.
    func flushPendingTerminalOutput() {
        guard let snapshot,
              let callID = snapshot.activeCallID else {
            return
        }
        outputFlushTask?.cancel()
        outputFlushTask = nil
        publishTerminalOutput(runID: snapshot.runID, callID: callID)
    }

    private func scheduleOutputFlush(runID: UUID, callID: String) {
        guard outputFlushTask == nil else { return }
        outputFlushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.outputPublishInterval)
            } catch {
                return
            }
            guard let self else { return }
            self.outputFlushTask = nil
            self.publishTerminalOutput(runID: runID, callID: callID)
        }
    }

    private func publishTerminalOutput(runID: UUID, callID: String) {
        guard let snapshot,
              snapshot.runID == runID,
              snapshot.activeAssistantMessageID != nil,
              snapshot.activeCallID == callID else {
            return
        }
        self.snapshot = ChatToolLiveSnapshot(
            runID: snapshot.runID,
            conversationID: snapshot.conversationID,
            assistantMessageIDs: snapshot.assistantMessageIDs,
            activeAssistantMessageID: snapshot.activeAssistantMessageID,
            activeCallID: snapshot.activeCallID,
            terminalOutput: accumulatedTerminalOutput
        )
    }

    func completeTool(callID: String, runID: UUID) {
        guard let snapshot,
              snapshot.runID == runID,
              snapshot.activeCallID == callID else {
            return
        }
        resetOutputBuffer()
        self.snapshot = ChatToolLiveSnapshot(
            runID: snapshot.runID,
            conversationID: snapshot.conversationID,
            assistantMessageIDs: snapshot.assistantMessageIDs,
            activeAssistantMessageID: nil,
            activeCallID: nil,
            terminalOutput: ""
        )
    }

    func endRun(runID: UUID) {
        guard snapshot?.runID == runID else { return }
        resetOutputBuffer()
        mostRecentAssistantMessageID = nil
        snapshot = nil
    }

    func snapshot(for conversationID: UUID) -> ChatToolLiveSnapshot? {
        guard snapshot?.conversationID == conversationID else { return nil }
        return snapshot
    }

    private func resetOutputBuffer() {
        outputFlushTask?.cancel()
        outputFlushTask = nil
        accumulatedTerminalOutput = ""
    }
}
