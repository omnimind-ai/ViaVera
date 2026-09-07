import SwiftUI

struct ModelUsageHeatmapLegend: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption) private var cellSize = ModelUsageStyle.heatCell

    var body: some View {
        HStack(spacing: ModelUsageStyle.heatGap) {
            Text("少")
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(ModelUsageStyle.heatColor(
                        count: level, maximum: 4, increasedContrast: contrast == .increased
                    ))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("多")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("颜色由浅到深表示消息数量由少到多")
    }
}
