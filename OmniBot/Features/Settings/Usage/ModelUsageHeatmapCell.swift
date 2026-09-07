import SwiftUI

struct ModelUsageHeatmapCell: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .caption) private var cellSize = ModelUsageStyle.heatCell

    let day: ModelUsageDay?
    let maximum: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(ModelUsageStyle.heatColor(
                count: day?.messageCount ?? 0,
                maximum: maximum,
                increasedContrast: contrast == .increased
            ))
            .overlay {
                if differentiateWithoutColor, let day, day.messageCount > 0 {
                    Circle()
                        .fill(.primary)
                        .padding(cellSize / 3)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .opacity(day == nil ? 0 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(day?.date.formatted(.dateTime.year().month().day().weekday()) ?? "")
            .accessibilityValue("\(day?.messageCount ?? 0) 条消息")
            .accessibilityHidden(day == nil)
            .help(day.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)) · \($0.messageCount) 条消息" } ?? "")
    }
}
