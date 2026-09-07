import SwiftUI

struct ModelUsageTokenBreakdown: View {
    let usage: ModelUsageDay
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.standardSpacing) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], spacing: AppDesign.standardSpacing) {
                ModelUsageMetric(title: "非缓存输入", value: usage.inputTokens, systemImage: "arrow.up.right")
                    .tint(ModelUsageStyle.input)
                ModelUsageMetric(title: "缓存读取", value: usage.cachedTokens, systemImage: "arrow.trianglehead.2.clockwise")
                    .tint(ModelUsageStyle.cache)
                ModelUsageMetric(title: "输出", value: usage.outputTokens, systemImage: "arrow.down.left")
                    .tint(ModelUsageStyle.output)
            }
            if usage.cacheCreationTokens > 0 {
                Text("输入中包含 \(usage.cacheCreationTokens.formatted()) Token 缓存写入")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppDesign.standardSpacing)
        .background(.primary.opacity(0.025), in: .rect(cornerRadius: AppDesign.standardSpacing))
    }
}
