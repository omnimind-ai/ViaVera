import SwiftUI

struct ModelUsageHeatmap: View {
    let summary: ModelUsageSummary
    @ScaledMetric(relativeTo: .caption) private var cellSize = ModelUsageStyle.heatCell

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private var maximum: Int { summary.peakDay?.messageCount ?? 0 }

    var body: some View {
        ModelUsagePanel(
            title: "对话活跃度",
            subtitle: "每一格是一天，颜色越深，发送的消息越多。",
            systemImage: "square.grid.3x3"
        ) {
            HStack(alignment: .top, spacing: AppDesign.compactSpacing) {
                VStack(spacing: ModelUsageStyle.heatGap) {
                    Color.clear.frame(height: cellSize)
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: cellSize)
                    }
                }
                .accessibilityHidden(true)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: ModelUsageStyle.heatGap) {
                        ForEach(summary.weeks) { week in
                            VStack(spacing: ModelUsageStyle.heatGap) {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                                    .overlay(alignment: .leading) {
                                        if let label = week.monthLabel {
                                            Text(label)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .fixedSize()
                                                .accessibilityHidden(true)
                                        }
                                    }
                                ForEach(0..<7) { row in
                                    ModelUsageHeatmapCell(day: week.days[row], maximum: maximum)
                                }
                            }
                        }
                    }
                    .padding(.trailing, AppDesign.contentPadding)
                }
                .defaultScrollAnchor(.trailing)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("最长连续 \(summary.longestStreak) 天")
                    Spacer()
                    ModelUsageHeatmapLegend()
                }
                VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
                    Text("最长连续 \(summary.longestStreak) 天")
                    ModelUsageHeatmapLegend()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
