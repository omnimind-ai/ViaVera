import SwiftUI

struct TerminalActivityThumbnail: View {
    let tool: ToolCallPresentation

    @State private var isShowingDetail = false

    var body: some View {
        Button(action: showDetail) {
            VStack(alignment: .leading, spacing: 2) {
                Text(promptLine)
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(previewText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color(red: 0.54, green: 0.93, blue: 0.65))
                    .lineLimit(3)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(
                width: AppDesign.toolActivityPreviewWidth,
                height: AppDesign.toolActivityPreviewHeight,
                alignment: .topLeading
            )
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.09),
                        Color(red: 0.035, green: 0.055, blue: 0.045),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(.rect(cornerRadius: AppDesign.compactCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
                    .strokeBorder(Color.white.opacity(0.08))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("打开 \(tool.title) 的工具输出")
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

    private var promptLine: String {
        if let command = tool.command?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            if let workingDirectory = tool.workingDirectory?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
               !workingDirectory.isEmpty {
                return "$ cd \(workingDirectory) && \(command)"
            }
            return "$ \(command)"
        }
        return "$ \(tool.name)"
    }

    private var previewText: String {
        let normalizedOutput = tool.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedOutput.isEmpty {
            return tool.status == .running ? "正在等待输出…" : "没有输出"
        }
        let lines = normalizedOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(3).joined(separator: "\n")
    }

    private func showDetail() {
        isShowingDetail = true
    }
}
