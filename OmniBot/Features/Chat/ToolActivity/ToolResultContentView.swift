import SwiftUI

struct ToolResultContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let tool: ToolCallPresentation
    let showsTitle: Bool

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                if showsTitle {
                    Text(tool.title)
                        .font(.title3)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label(tool.typeLabel, systemImage: tool.symbolName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let id = nativeToolID {
                    Button("打开工具", systemImage: "square.grid.2x2") {
                        dismiss()
                        appModel.openNativeTool(id)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if tool.isTerminal {
                    Text(tool.terminalTranscript)
                        .font(.callout.monospaced())
                        .foregroundStyle(Color(red: 0.82, green: 0.90, blue: 0.84))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                        .padding()
                        .background(Color(red: 0.035, green: 0.055, blue: 0.045))
                        .clipShape(.rect(cornerRadius: AppDesign.compactCornerRadius))
                } else if tool.output.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    ContentUnavailableView {
                        Label("还没有结果", systemImage: "hourglass")
                    } description: {
                        Text(tool.status == .running || tool.status == .pending
                             ? "工具仍在执行。"
                             : "工具没有返回可显示的正文。")
                    }
                    .frame(minHeight: 140)
                } else {
                    Text(tool.output)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(.rect(cornerRadius: AppDesign.compactCornerRadius))
                }
            }
            .padding(AppDesign.contentPadding)
            .frame(maxWidth: AppDesign.chatContentMaximumWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var nativeToolID: UUID? {
        guard tool.name == "native_tool_install", tool.status == .succeeded,
              let metadata = try? JSONDecoder().decode(AgentValue.self, from: Data(tool.metadata.utf8)),
              let urlString = metadata.objectValue?["openURL"]?.stringValue,
              let url = URL(string: urlString) else { return nil }
        return NativeToolRecord.identifier(from: url)
    }
}
