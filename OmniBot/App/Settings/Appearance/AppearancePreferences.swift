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

    var themeMode: AppearanceThemeMode
    var backgroundOpacity: Double
    var backgroundBrightness: Double
    var backgroundBlur: Double

    init(
        themeMode: AppearanceThemeMode = .system,
        backgroundOpacity: Double,
        backgroundBrightness: Double,
        backgroundBlur: Double
    ) {
        self.themeMode = themeMode
        self.backgroundOpacity = backgroundOpacity
        self.backgroundBrightness = backgroundBrightness
        self.backgroundBlur = backgroundBlur
    }

    private enum CodingKeys: String, CodingKey {
        case themeMode
        case backgroundOpacity
        case backgroundBrightness
        case backgroundBlur
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Existing appearance files predate the theme preference.
        themeMode = try container.decodeIfPresent(
            AppearanceThemeMode.self,
            forKey: .themeMode
        ) ?? .system
        backgroundOpacity = try container.decode(Double.self, forKey: .backgroundOpacity)
        backgroundBrightness = try container.decode(Double.self, forKey: .backgroundBrightness)
        backgroundBlur = try container.decode(Double.self, forKey: .backgroundBlur)
    }

    var normalized: AppearancePreferences {
        AppearancePreferences(
            themeMode: themeMode,
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
