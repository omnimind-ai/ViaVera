import SwiftUI

struct AppearanceAdjustmentRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: AppDesign.standardSpacing) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: AppDesign.compactSpacing)

                Text(valueText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityHidden(true)

            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue(valueText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppDesign.compactSpacing / 2)
    }
}
