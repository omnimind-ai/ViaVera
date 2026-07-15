import Foundation

struct AgentTurnExpansionState {
    // Active turns expand structurally and never enter this set. Keeping only
    // explicit user choices makes a run collapse naturally when it completes.
    private(set) var manuallyExpandedTurnIDs: Set<UUID> = []
    private(set) var expansionOrder: [UUID] = []

    func isManuallyExpanded(_ turnID: UUID) -> Bool {
        manuallyExpandedTurnIDs.contains(turnID)
    }

    mutating func toggle(_ turnID: UUID) {
        if manuallyExpandedTurnIDs.remove(turnID) != nil {
            expansionOrder.removeAll { $0 == turnID }
        } else {
            manuallyExpandedTurnIDs.insert(turnID)
            expansionOrder.removeAll { $0 == turnID }
            expansionOrder.append(turnID)
        }
    }

    mutating func collapse(_ turnID: UUID) {
        manuallyExpandedTurnIDs.remove(turnID)
        expansionOrder.removeAll { $0 == turnID }
    }

    mutating func reset() {
        manuallyExpandedTurnIDs.removeAll()
        expansionOrder.removeAll()
    }

    func preferredCompletedTurnID(in turns: [AgentTurnPresentation]) -> UUID? {
        let completedTurnIDs = Set(turns.lazy.filter { !$0.isActive }.map(\.id))
        return expansionOrder.reversed().first {
            manuallyExpandedTurnIDs.contains($0) && completedTurnIDs.contains($0)
        }
    }
}
