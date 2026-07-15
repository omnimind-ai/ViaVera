import SwiftUI

struct ToolCallCapsule: View {
    let tool: ToolCallPresentation

    @State private var isShowingDetail = false

    var body: some View {
        Button(action: showDetail) {
            HStack(spacing: 8) {
                Image(systemName: tool.symbolName)
                    .font(.footnote)
                    .accessibilityHidden(true)

                Text(tool.title)
                    .font(.footnote)
                    .lineLimit(1)

                Label(tool.status.label, systemImage: tool.status.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: AppDesign.toolCapsuleVisualHeight)
            .foregroundStyle(.primary)
            .background(statusColor.opacity(0.10), in: .capsule)
            .frame(minHeight: AppDesign.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.title)，\(tool.typeLabel)，\(tool.status.label)")
        .accessibilityHint("打开工具调用结果")
#if os(macOS)
        .popover(isPresented: $isShowingDetail, arrowEdge: .bottom) {
            ToolResultSheet(tool: tool)
        }
#else
        .sheet(isPresented: $isShowingDetail) {
            ToolResultSheet(tool: tool)
        }
#endif
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

    private func showDetail() {
        isShowingDetail = true
    }
}
