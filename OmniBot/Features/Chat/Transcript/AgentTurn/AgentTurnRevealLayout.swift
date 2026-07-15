import SwiftUI

@Animatable
struct AgentTurnRevealLayout: Layout {
    var progress: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        // Never feed the animated container height back into text layout.
        // The content is always measured at its full height for a stable width.
        let contentProposal = ProposedViewSize(
            width: proposal.width,
            height: nil
        )
        let contentSize = subview.sizeThatFits(contentProposal)
        let normalizedProgress: CGFloat
        if progress < 0 {
            normalizedProgress = 0
        } else if progress > 1 {
            normalizedProgress = 1
        } else {
            normalizedProgress = progress
        }
        return CGSize(
            width: contentSize.width,
            // Publishing the interpolated height from Layout keeps following
            // transcript rows synchronized with the clipped process content.
            height: contentSize.height * normalizedProgress
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let contentProposal = ProposedViewSize(width: bounds.width, height: nil)
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: contentProposal
        )
    }
}
