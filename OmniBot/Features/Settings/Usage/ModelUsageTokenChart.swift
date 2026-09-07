import Charts
import SwiftUI

struct ModelUsageTokenChart: View {
    let summary: ModelUsageSummary
    @State private var selectedDate: String?
    @ScaledMetric(relativeTo: .body) private var chartHeight = ModelUsageStyle.chartHeight

    private var selectedBucket: ModelUsageDay? {
        guard let selectedDate else { return nil }
        return summary.tokenBuckets.first { label(for: $0) == selectedDate }
    }

    var body: some View {
        ModelUsagePanel(
            title: "Token 使用趋势",
            subtitle: "\(summary.range.bucketTitle)消耗分布 · 输入、缓存读取与输出",
            systemImage: "chart.bar.xaxis"
        ) {
            if summary.total.totalTokens > 0 {
                Chart(summary.tokenBuckets) { bucket in
                    BarMark(
                        x: .value("日期", label(for: bucket)),
                        y: .value("Token", bucket.inputTokens)
                    )
                    .foregroundStyle(by: .value("类型", "输入"))
                    .accessibilityLabel("\(label(for: bucket))，非缓存输入")
                    .accessibilityValue("\(bucket.inputTokens) Token")

                    BarMark(
                        x: .value("日期", label(for: bucket)),
                        y: .value("Token", bucket.cachedTokens)
                    )
                    .foregroundStyle(by: .value("类型", "缓存读取"))
                    .accessibilityLabel("\(label(for: bucket))，缓存读取")
                    .accessibilityValue("\(bucket.cachedTokens) Token")

                    BarMark(
                        x: .value("日期", label(for: bucket)),
                        y: .value("Token", bucket.outputTokens)
                    )
                    .foregroundStyle(by: .value("类型", "输出"))
                    .accessibilityLabel("\(label(for: bucket))，输出")
                    .accessibilityValue("\(bucket.outputTokens) Token")

                    if let selectedBucket, selectedBucket.id == bucket.id {
                        RuleMark(x: .value("选中日期", label(for: bucket)))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .accessibilityHidden(true)
                    }
                }
                .chartForegroundStyleScale([
                    "输入": ModelUsageStyle.input,
                    "缓存读取": ModelUsageStyle.cache,
                    "输出": ModelUsageStyle.output,
                ])
                .chartLegend(position: .bottom, alignment: .leading, spacing: AppDesign.standardSpacing)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text(count, format: .number.notation(.compactName))
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: chartHeight)
                .accessibilityLabel("Token 堆叠柱状图，横轴为日期，纵轴为 Token 数量")

                ModelUsageTokenBreakdown(usage: selectedBucket ?? summary.total, title: selectedBucket.map {
                    "\(label(for: $0))\(summary.range == .quarter ? " 起的一周" : "")"
                } ?? "所选时段合计")
            } else {
                ContentUnavailableView(
                    "暂无 Token 记录", systemImage: "chart.bar",
                    description: Text("模型返回用量后，消耗趋势会显示在这里。")
                )
            }
        }
        .onChange(of: summary.range) { selectedDate = nil }
    }

    private func label(for bucket: ModelUsageDay) -> String {
        if summary.range == .year {
            bucket.date.formatted(.dateTime.year().month(.abbreviated))
        } else {
            bucket.date.formatted(.dateTime.month().day())
        }
    }
}
