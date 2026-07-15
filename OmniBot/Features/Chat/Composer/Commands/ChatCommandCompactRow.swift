import SwiftUI

struct ChatCommandCompactRow: View {
    let isBusy: Bool
    let isCompacting: Bool
    let compactionMessage: String?
    let compactionFailed: Bool
    let onCompact: () -> Void

    var body: some View {
        Button(action: onCompact) {
            HStack(spacing: AppDesign.compactSpacing) {
                Text("compact")
                    .font(.caption)
                    .bold()
                    .lineLimit(1)

                Spacer(minLength: AppDesign.compactSpacing)

                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isCompacting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity)
            .frame(height: AppDesign.toolActivityVisualRowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(height: AppDesign.minimumTouchTarget)
        .padding(
            .vertical,
            -(AppDesign.minimumTouchTarget - AppDesign.toolActivityVisualRowHeight) / 2
        )
        .disabled(isBusy)
        .accessibilityLabel("compact，\(detailText)")
    }

    private var detailText: String {
        if isCompacting {
            "正在压缩上下文…"
        } else if let compactionMessage, !compactionMessage.isEmpty {
            compactionMessage
        } else {
            "手动压缩当前对话上下文"
        }
    }

    private var detailColor: Color {
        compactionFailed ? .red : .secondary
    }
}
