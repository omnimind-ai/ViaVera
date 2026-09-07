import SwiftData
import SwiftUI

struct ModelUsageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = ModelUsageViewModel()
    @State private var range = ModelUsageRange.quarter
    @State private var refreshID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.contentPadding) {
                VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
                    Text("统计时段")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    if dynamicTypeSize.isAccessibilitySize {
                        Picker("统计时段", selection: $range) {
                            ForEach(ModelUsageRange.allCases) { range in
                                Text(range.title).tag(range)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        Picker("统计时段", selection: $range) {
                            ForEach(ModelUsageRange.allCases) { range in
                                Text(range.title).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let errorMessage = model.errorMessage {
                    ContentUnavailableView {
                        Label("用量读取失败", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重新加载", action: refresh)
                            .frame(minHeight: 44)
                    }
                } else if let summary = model.summary {
                    ModelUsageOverview(summary: summary)
                    if !summary.hasActivity {
                        ContentUnavailableView(
                            "这个时段还没有对话", systemImage: "bubble.left.and.bubble.right",
                            description: Text("发送第一条消息，或切换时段查看已有记录。")
                        )
                    }
                    ModelUsageHeatmap(summary: summary)
                    ModelUsageTokenChart(summary: summary)
                    ModelUsageDistribution(summary: summary)
                } else {
                    ProgressView("正在整理用量…")
                        .frame(maxWidth: .infinity, minHeight: ModelUsageStyle.chartHeight)
                }
            }
            .padding(AppDesign.contentPadding)
            .frame(maxWidth: AppDesign.settingsContentMaximumWidth)
            .frame(maxWidth: .infinity)
        }
        .background(.primary.opacity(0.025))
#if !os(macOS)
        .navigationTitle("模型用量")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新用量", systemImage: "arrow.clockwise", action: refresh)
            }
        }
#endif
        .task(id: [String(range.rawValue), refreshID.uuidString]) { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { refresh() }
        }
    }

    private func refresh() { refreshID = UUID() }

    private func load() async {
        await model.load(container: modelContext.container, range: range)
    }
}
