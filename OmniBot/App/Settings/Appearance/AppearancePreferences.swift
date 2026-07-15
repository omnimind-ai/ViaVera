import Foundation

nonisolated struct AppearancePreferences: Codable, Equatable, Sendable {
    static let opacityRange = 0.0...1.0
    static let brightnessRange = -0.5...0.5
    static let blurRange = 0.0...30.0

    static let defaultValue = AppearancePreferences(
        backgroundOpacity: 0.35,
        backgroundBrightness: 0,
        backgroundBlur: 8
    )

    var backgroundOpacity: Double
    var backgroundBrightness: Double
    var backgroundBlur: Double

    init(
        backgroundOpacity: Double,
        backgroundBrightness: Double,
        backgroundBlur: Double
    ) {
        self.backgroundOpacity = backgroundOpacity
        self.backgroundBrightness = backgroundBrightness
        self.backgroundBlur = backgroundBlur
    }

    var normalized: AppearancePreferences {
        AppearancePreferences(
            backgroundOpacity: Self.clamp(
                backgroundOpacity,
                to: Self.opacityRange,
                fallback: Self.defaultValue.backgroundOpacity
            ),
            backgroundBrightness: Self.clamp(
                backgroundBrightness,
                to: Self.brightnessRange,
                fallback: Self.defaultValue.backgroundBrightness
            ),
            backgroundBlur: Self.clamp(
                backgroundBlur,
                to: Self.blurRange,
                fallback: Self.defaultValue.backgroundBlur
            )
        )
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
