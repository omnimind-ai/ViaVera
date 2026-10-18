import Foundation

struct TranscriptDisclosureState {
    private(set) var isMounted: Bool
    private(set) var progress: CGFloat
    private(set) var revision = 0

    init(isExpanded: Bool) {
        isMounted = isExpanded
        progress = isExpanded ? 1 : 0
    }

    mutating func setExpanded(_ isExpanded: Bool) {
        revision &+= 1
        if isExpanded { isMounted = true }
        progress = isExpanded ? 1 : 0
    }

    mutating func finishCollapse(revision completedRevision: Int) {
        // An interrupted closing animation must not remove reopened content.
        guard revision == completedRevision, progress == 0 else { return }
        isMounted = false
    }
}
