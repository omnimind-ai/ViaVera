import SwiftUI

struct MessageResponseDetailsView: View {
    let completion: ResponseCompletionPresentation

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                tokenMetrics
                timingMetrics
            }
            VStack(alignment: .leading, spacing: 6) {
                tokenMetrics
                timingMetrics
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var tokenMetrics: some View {
        HStack(spacing: 12) {
            UsageMetricLabel(
                symbol: "arrow.up",
                value: TokenCountFormatter.format(completion.usage.contextTokens)
            )
            .help("上行 token（含缓存读取）")
            .accessibilityLabel(String(localized: "上行 token：\(completion.usage.contextTokens)"))
            UsageMetricLabel(
                symbol: "arrow.down",
                value: TokenCountFormatter.format(completion.usage.outputTokens)
            )
            .help("下行 token")
            .accessibilityLabel(String(localized: "下行 token：\(completion.usage.outputTokens)"))
            UsageMetricLabel(symbol: "cylinder.split.1x2", value: cacheLabel)
                .help(cacheDescription)
                .accessibilityLabel(cacheDescription)
        }
        .fixedSize()
    }

    private var timingMetrics: some View {
        HStack(spacing: 12) {
            UsageMetricLabel(symbol: "stopwatch", value: completion.elapsedLabel)
                .help("响应耗时")
                .accessibilityLabel(String(localized: "响应耗时：\(completion.elapsedLabel)"))
            Label {
                Text(completion.completedAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
            }
            .help("完成时间")
            .accessibilityLabel(Text("完成时间：\(completion.completedAt, format: .dateTime.hour().minute())"))
        }
        .fixedSize()
    }

    private var cacheLabel: String {
        guard let percentage = completion.usage.cacheHitPercentage else { return "—" }
        return "\(TokenCountFormatter.format(completion.usage.cachedTokens)) · \(percentage)%"
    }

    private var cacheDescription: String {
        guard let percentage = completion.usage.cacheHitPercentage else {
            return String(localized: "模型未提供缓存用量")
        }
        return String(localized: "缓存读取 \(completion.usage.cachedTokens) token，命中率 \(percentage)%，缓存写入 \(completion.usage.cacheCreationTokens) token")
    }
}
