import SwiftUI

struct ChatCommandToolbar: View {
    let selectedEffort: AgentReasoningEffort?
    let isBusy: Bool
    let isCompacting: Bool
    let compactionMessage: String?
    let compactionFailed: Bool
    let onCompact: () -> Void
    let onSelectEffort: (AgentReasoningEffort) -> Void

    var body: some View {
        ChatActivitySurface {
            VStack(spacing: 0) {
                ChatCommandEffortRow(
                    selectedEffort: selectedEffort,
                    isBusy: isBusy,
                    onSelectEffort: onSelectEffort
                )

                Divider()
                    .padding(.leading, 18)

                ChatCommandCompactRow(
                    isBusy: isBusy,
                    isCompacting: isCompacting,
                    compactionMessage: compactionMessage,
                    compactionFailed: compactionFailed,
                    onCompact: onCompact
                )
            }
        }
        .frame(maxWidth: AppDesign.composerMaximumWidth)
        .padding(.horizontal, AppDesign.composerHorizontalInset)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
