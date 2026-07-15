import SwiftUI

struct ChatToolActivityStrip: View {
    let conversationID: UUID
    let tools: [ToolCallPresentation]
    let isRunning: Bool
    @Binding var isExpanded: Bool
    let onCancel: (String) async -> Bool
    let onOpenBrowser: () -> Void

    @State private var stoppingToolID: String?
    @State private var selectedTool: ToolCallPresentation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let currentTool {
            let history = historyTools(currentTool: currentTool)
            let showsToolPreview = !isExpanded
            let historyHeight = min(
                Double(history.count) * AppDesign.toolActivityVisualRowHeight,
                AppDesign.toolActivityVisualRowHeight * 5
            )
            // Keep the composer inset stable; expanded history overflows
            // upward instead of pushing the input surface and transcript.
            let previewExtension = AppDesign.toolActivityPreviewHeight
                - AppDesign.toolActivityPreviewOverlap
            let occupiedHeight = AppDesign.toolActivityVisualRowHeight + previewExtension
            let previewVerticalOffset = AppDesign.toolActivityPreviewHeight - occupiedHeight
            ZStack(alignment: .bottomLeading) {
                ChatActivitySurface {
                    VStack(spacing: 0) {
                        if isExpanded && !history.isEmpty {
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 0) {
                                    ForEach(history) { tool in
                                        ToolActivityRow(
                                            tool: tool,
                                            leadingInset: 0,
                                            contentHeight: AppDesign.toolActivityVisualRowHeight,
                                            onSelect: { selectedTool = tool }
                                        )
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .defaultScrollAnchor(.bottom)
                            .frame(height: historyHeight)

                            Divider()
                                .padding(.leading, 18)
                        }

                        HStack(spacing: 0) {
                            ToolActivityRow(
                                tool: currentTool,
                                leadingInset: showsToolPreview
                                    ? AppDesign.toolActivityPreviewLeadingInset
                                    : 0,
                                contentHeight: AppDesign.toolActivityVisualRowHeight,
                                onSelect: {
                                    selectCurrentTool(currentTool, hasHistory: !history.isEmpty)
                                }
                            )

                            if isRunning
                                && currentTool.status == .running
                                && isStoppableTerminal(currentTool) {
                                Button(action: { stop(currentTool) }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.secondary.opacity(0.10))
                                            .overlay {
                                                Circle()
                                                    .strokeBorder(.secondary.opacity(0.42))
                                            }
                                            .frame(width: 20, height: 20)

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.secondary)
                                            .frame(width: 7, height: 7)
                                    }
                                    .frame(
                                        width: AppDesign.toolActivityVisualRowHeight,
                                        height: AppDesign.toolActivityVisualRowHeight
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(
                                    width: AppDesign.minimumTouchTarget,
                                    height: AppDesign.minimumTouchTarget
                                )
                                .padding(
                                    -(AppDesign.minimumTouchTarget
                                      - AppDesign.toolActivityVisualRowHeight) / 2
                                )
                                .disabled(stoppingToolID == currentTool.id)
                                .accessibilityLabel(
                                    stoppingToolID == currentTool.id
                                        ? "正在停止当前工具"
                                        : "停止当前工具"
                                )
                            } else if !history.isEmpty {
                                Button(action: toggleExpanded) {
                                    Label(
                                        isExpanded ? "收起历史工具调用" : "展开历史工具调用",
                                        systemImage: "chevron.up"
                                    )
                                    .labelStyle(.iconOnly)
                                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
                                    .frame(
                                        width: AppDesign.toolActivityVisualRowHeight,
                                        height: AppDesign.toolActivityVisualRowHeight
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(
                                    width: AppDesign.minimumTouchTarget,
                                    height: AppDesign.minimumTouchTarget
                                )
                                .padding(
                                    -(AppDesign.minimumTouchTarget
                                      - AppDesign.toolActivityVisualRowHeight) / 2
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: AppDesign.toolActivityVisualRowHeight)
                    }
                }

                if showsToolPreview {
                    Group {
                        if currentTool.isBrowser {
                            BrowserActivityThumbnail(
                                conversationID: conversationID,
                                tool: currentTool,
                                onOpenBrowser: onOpenBrowser
                            )
                        } else {
                            TerminalActivityThumbnail(tool: currentTool)
                        }
                    }
                        .offset(y: previewVerticalOffset)
                        .zIndex(1)
                }
            }
            .frame(height: occupiedHeight, alignment: .bottom)
            .zIndex(isExpanded ? 2 : 0)
            .frame(maxWidth: AppDesign.composerMaximumWidth)
            .padding(.horizontal, AppDesign.composerHorizontalInset)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isExpanded)
            .onChange(of: currentTool.id) { _, identifier in
                if stoppingToolID != identifier {
                    stoppingToolID = nil
                }
            }
            .onChange(of: currentTool.status) { _, status in
                if status != .running {
                    stoppingToolID = nil
                }
            }
            .onChange(of: history.isEmpty, initial: true) { _, isEmpty in
                if isEmpty {
                    isExpanded = false
                }
            }
#if os(macOS)
            .popover(item: $selectedTool, arrowEdge: .bottom) { tool in
                ToolResultSheet(tool: tool)
            }
#else
            .sheet(item: $selectedTool) { tool in
                ToolResultSheet(tool: tool)
            }
#endif
        }
    }

    private var currentTool: ToolCallPresentation? {
        if isRunning {
            return tools.first(where: { $0.status == .running })
                ?? tools.last
        }
        return tools.last
    }

    private func historyTools(
        currentTool: ToolCallPresentation
    ) -> [ToolCallPresentation] {
        tools.filter {
            $0.id != currentTool.id && $0.status != .pending
        }
    }

    private func selectCurrentTool(
        _ tool: ToolCallPresentation,
        hasHistory: Bool
    ) {
        if isRunning {
            if hasHistory {
                toggleExpanded()
            }
            return
        }
        selectedTool = tool
    }

    private func toggleExpanded() {
        isExpanded.toggle()
    }

    private func stop(_ tool: ToolCallPresentation) {
        guard stoppingToolID == nil else { return }
        stoppingToolID = tool.id
        Task {
            let didRequestStop = await onCancel(tool.callID)
            if !didRequestStop {
                stoppingToolID = nil
            }
        }
    }

    private func isStoppableTerminal(_ tool: ToolCallPresentation) -> Bool {
        tool.name == "terminal_execute" || tool.name == "terminal_session_exec"
    }
}
