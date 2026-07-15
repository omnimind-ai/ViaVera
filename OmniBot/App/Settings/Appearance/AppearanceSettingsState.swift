import Foundation

nonisolated struct AppearanceSettingsState: Sendable {
    let preferences: AppearancePreferences
    let backgroundImageData: Data?
}
