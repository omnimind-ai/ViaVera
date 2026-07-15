import SwiftUI

struct ChatCommandEffortRow: View {
    let selectedEffort: AgentReasoningEffort?
    let isBusy: Bool
    let onSelectEffort: (AgentReasoningEffort) -> Void

    var body: some View {
        HStack(spacing: AppDesign.compactSpacing) {
            Text("effort")
                .font(.caption)
                .bold()
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: AppDesign.compactSpacing)

            ChatCommandEffortPicker(
                selectedEffort: selectedEffort,
                isDisabled: isBusy,
                onSelect: onSelectEffort
            )
            .frame(maxWidth: 240)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
        .frame(height: AppDesign.toolActivityVisualRowHeight)
    }
}
