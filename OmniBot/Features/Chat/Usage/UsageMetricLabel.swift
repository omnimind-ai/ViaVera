import SwiftUI

struct UsageMetricLabel: View {
    let symbol: String
    let value: String
    var prefix = ""

    var body: some View {
        Label {
            Text("\(prefix)\(value)")
                .monospacedDigit()
        } icon: {
            Image(systemName: symbol)
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
    }
}
