import SwiftUI

struct ModelUsageOverview: View {
    let summary: ModelUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.contentPadding) {
            VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
                Label("Token 总用量", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(summary.total.totalTokens, format: .number.notation(.compactName))
                    .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(ModelUsageStyle.accent)
                    .accessibilityLabel("Token 总用量")
                    .accessibilityValue(summary.total.totalTokens.formatted())
                Text("\(summary.total.totalTokens.formatted()) Token · \(summary.total.responseCount.formatted()) 次模型响应")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(ModelUsageStyle.accent.opacity(0.12))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], spacing: AppDesign.sectionSpacing) {
                ModelUsageMetric(title: "发送消息", value: summary.total.messageCount, systemImage: "bubble.left")
                ModelUsageMetric(title: "活跃天数", value: summary.activeDays, systemImage: "calendar")
                ModelUsageMetric(title: "使用模型", value: summary.knownModelCount, systemImage: "cpu")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppDesign.contentPadding)
        .background {
            RoundedRectangle(cornerRadius: ModelUsageStyle.cornerRadius)
                .fill(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: ModelUsageStyle.cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [ModelUsageStyle.accent.opacity(0.12), Color.indigo.opacity(0.025)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
        }
    }
}
