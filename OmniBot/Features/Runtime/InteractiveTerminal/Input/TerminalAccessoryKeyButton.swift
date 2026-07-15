import SwiftUI

struct TerminalAccessoryKeyButton: View {
    let item: TerminalAccessoryKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .bold()
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: .rect(cornerRadius: AppDesign.compactCornerRadius)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(minWidth: AppDesign.minimumTouchTarget)
        .frame(height: AppDesign.terminalAccessoryKeyHeight)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(isSelected ? "已锁定" : "")
    }
}
