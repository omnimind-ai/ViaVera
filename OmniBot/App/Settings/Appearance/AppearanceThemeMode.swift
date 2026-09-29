import SwiftUI

nonisolated enum AppearanceThemeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .dark: String(localized: "黑夜")
        case .light: String(localized: "白天")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}
