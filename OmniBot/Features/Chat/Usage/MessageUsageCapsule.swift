import SwiftUI

struct MessageUsageCapsule: View {
    let contextTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int

    var body: some View {
        HStack(spacing: 8) {
            UsageMetricLabel(
                symbol: "gauge.with.dots.needle.33percent",
                value: TokenCountFormatter.format(contextTokens),
                prefix: "ctx:"
            )
            UsageMetricLabel(
                symbol: "arrow.down",
                value: TokenCountFormatter.format(inputTokens)
            )
            UsageMetricLabel(
                symbol: "arrow.up",
                value: TokenCountFormatter.format(outputTokens)
            )
            UsageMetricLabel(
                symbol: "cylinder.split.1x2",
                value: TokenCountFormatter.format(cachedTokens)
            )
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "当前上下文 \(TokenCountFormatter.format(contextTokens))，输入 \(TokenCountFormatter.format(inputTokens))，输出 \(TokenCountFormatter.format(outputTokens))，缓存 \(TokenCountFormatter.format(cachedTokens))"
        )
    }
}
