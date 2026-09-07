import Charts
import SwiftUI

struct ModelUsageModelBar: View {
    let model: ModelUsageModel
    let metric: ModelUsageRankingMetric
    let maximum: Int
    let total: Int

    private var value: Int { metric.value(for: model) }
    private var fraction: Double { Double(value) / Double(max(1, total)) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: AppDesign.standardSpacing) {
                    Text(model.title).font(.subheadline.bold())
                    Spacer(minLength: AppDesign.compactSpacing)
                    Text("\(value.formatted()) · \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: ModelUsageStyle.heatGap) {
                    Text(model.title).font(.subheadline.bold()).textSelection(.enabled)
                    Text("\(value.formatted()) · \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                BarMark(x: .value("范围", max(1, maximum)), y: .value("模型", model.title))
                    .foregroundStyle(.primary.opacity(0.045))
                BarMark(x: .value(metric.rawValue, value), y: .value("模型", model.title), stacking: .unstacked)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ModelUsageStyle.input.opacity(0.75), ModelUsageStyle.accent],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(4)
            }
            .chartXScale(domain: 0...max(1, maximum))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 10)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.title)
        .accessibilityValue("\(metric.rawValue) \(value.formatted())，占比 \(fraction.formatted(.percent.precision(.fractionLength(1))))")
    }
}
