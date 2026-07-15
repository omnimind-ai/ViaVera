import SwiftUI

struct UserMessageContentView: View {
    let content: String
    let showsEditAffordance: Bool

    var body: some View {
        Text(content)
            .font(.body)
            .foregroundStyle(.primary)
            .underline(
                showsEditAffordance,
                pattern: .dash,
                color: .secondary
            )
            .padding(.horizontal, AppDesign.userMessageHorizontalPadding)
            .padding(.vertical, AppDesign.userMessageVerticalPadding)
            .background(
                Color.secondary.opacity(0.11),
                in: .rect(cornerRadius: AppDesign.userMessageCornerRadius)
            )
#if os(iOS)
            .background(
                AppDesign.chatBackground,
                in: .rect(cornerRadius: AppDesign.userMessageCornerRadius)
            )
            .contentShape(
                [.interaction, .contextMenuPreview],
                .rect(cornerRadius: AppDesign.userMessageCornerRadius)
            )
#else
            .contentShape(
                .interaction,
                .rect(cornerRadius: AppDesign.userMessageCornerRadius)
            )
#endif
    }
}
