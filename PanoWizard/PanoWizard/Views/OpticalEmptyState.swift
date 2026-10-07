import SwiftUI

/// Keeps the message's center near the upper third, with room for tall content.
private struct OpticalEmptyStateLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let content = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? content.width, height: proposal.height ?? content.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let contentProposal = ProposedViewSize(width: bounds.width, height: nil)
        let height = subviews[0].sizeThatFits(contentProposal).height
        let centerY = min(max(bounds.height / 3, height / 2), max(height / 2, bounds.height - height / 2))
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY + centerY), anchor: .center, proposal: contentProposal)
    }
}

extension View {
    func opticalEmptyState() -> some View {
        OpticalEmptyStateLayout { self.fixedSize(horizontal: false, vertical: true) }
    }
}
