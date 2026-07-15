import SwiftUI

struct ToolActivityRow: View {
    let tool: ToolCallPresentation
    let leadingInset: Double
    let contentHeight: Double
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.18))
                        .frame(width: 9, height: 9)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 4, height: 4)
                }
                .accessibilityHidden(true)

                Text(tool.title)
                    .font(.caption)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(tool.typeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(tool.status.label)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.11), in: .capsule)
            }
            .padding(.leading, 10 + leadingInset)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity)
            .frame(height: contentHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(height: AppDesign.minimumTouchTarget)
        .padding(
            .vertical,
            -(AppDesign.minimumTouchTarget - contentHeight) / 2
        )
        .accessibilityLabel("\(tool.title)，\(tool.typeLabel)，\(tool.status.label)")
    }

    private var statusColor: Color {
        switch tool.status {
        case .failed:
            .red
        case .succeeded:
            .green
        case .running:
            .accentColor
        case .pending, .interrupted:
            .secondary
        }
    }
}
