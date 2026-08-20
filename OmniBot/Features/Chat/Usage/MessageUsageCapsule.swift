import SwiftUI

struct MessageUsageCapsule: View {
    let contextTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let cacheCreationTokens: Int
    let cacheHitPercentage: Int?

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
            if let cacheHitPercentage {
                UsageMetricLabel(
                    symbol: "cylinder.split.1x2",
                    value: "\(cacheHitPercentage)%",
                    prefix: "hit:"
                )
            }
            if cacheCreationTokens > 0 {
                UsageMetricLabel(
                    symbol: "tray.and.arrow.down",
                    value: TokenCountFormatter.format(cacheCreationTokens),
                    prefix: "write:"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [
            "当前上下文 \(TokenCountFormatter.format(contextTokens))",
            "未命中输入 \(TokenCountFormatter.format(inputTokens))",
            "输出 \(TokenCountFormatter.format(outputTokens))",
        ]
        if let cacheHitPercentage {
            parts.append(
                "缓存命中率 \(cacheHitPercentage)%，命中读取 \(TokenCountFormatter.format(cachedTokens))"
            )
        }
        if cacheCreationTokens > 0 {
            parts.append("缓存写入 \(TokenCountFormatter.format(cacheCreationTokens))")
        }
        return parts.joined(separator: "，")
    }
}
