import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppearanceSettingsModel {
    var backgroundOpacity = AppearancePreferences.defaultValue.backgroundOpacity
    var backgroundBrightness = AppearancePreferences.defaultValue.backgroundBrightness
    var backgroundBlur = AppearancePreferences.defaultValue.backgroundBlur
    private(set) var backgroundImage: CGImage?
    var errorMessage: String?

    private let store: AppearanceSettingsStore

    init(store: AppearanceSettingsStore) {
        self.store = store
    }

    var preferences: AppearancePreferences {
        AppearancePreferences(
            backgroundOpacity: backgroundOpacity,
            backgroundBrightness: backgroundBrightness,
            backgroundBlur: backgroundBlur
        ).normalized
    }

    var hasBackgroundImage: Bool {
        backgroundImage != nil
    }

    func load() async {
        do {
            let state = try await store.load()
            backgroundOpacity = state.preferences.backgroundOpacity
            backgroundBrightness = state.preferences.backgroundBrightness
            backgroundBlur = state.preferences.backgroundBlur
            if let data = state.backgroundImageData {
                guard let image = AppearanceBackgroundImageDecoder.decode(data) else {
                    throw AppearanceSettingsStoreError.invalidImage
                }
                backgroundImage = image
            } else {
                backgroundImage = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ preferencesSnapshot: AppearancePreferences) async {
        do {
            let normalized = preferencesSnapshot.normalized
            try await store.save(normalized)
            if preferences == preferencesSnapshot {
                backgroundOpacity = normalized.backgroundOpacity
                backgroundBrightness = normalized.backgroundBrightness
                backgroundBlur = normalized.backgroundBlur
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replaceBackgroundImage(from sourceURL: URL) async {
        do {
            let data = try await store.replaceBackgroundImage(from: sourceURL)
            try applyBackgroundImage(data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replaceBackgroundImage(with data: Data) async {
        do {
            let storedData = try await store.replaceBackgroundImage(with: data)
            try applyBackgroundImage(storedData)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBackgroundImage() async {
        do {
            try await store.removeBackgroundImage()
            backgroundImage = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyBackgroundImage(_ data: Data) throws {
        guard let image = AppearanceBackgroundImageDecoder.decode(data) else {
            throw AppearanceSettingsStoreError.invalidImage
        }
        backgroundImage = image
    }
}
