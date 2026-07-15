import SwiftUI

struct AppearanceAdjustmentRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: AppDesign.compactSpacing / 2) {
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $value, in: range, step: step)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueText)
            }
        } label: {
            Text(title)
        }
    }
}
