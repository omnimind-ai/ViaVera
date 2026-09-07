import SwiftUI

enum ModelUsageStyle {
    static let accent = Color.teal
    static let input = Color.indigo
    static let output = Color.teal
    static let cache = Color.orange
    static let cornerRadius: Double = 20
    static let chartHeight: Double = 210
    static let heatCell: Double = 16
    static let heatGap: Double = 4

    static func heatColor(count: Int, maximum: Int, increasedContrast: Bool) -> Color {
        guard count > 0 else { return Color.primary.opacity(increasedContrast ? 0.16 : 0.055) }
        let fraction = Double(count) / Double(max(1, maximum))
        let level = min(4, max(1, Int(ceil(fraction * 4))))
        return accent.opacity((increasedContrast ? 0.38 : 0.2) + Double(level) * 0.15)
    }
}
