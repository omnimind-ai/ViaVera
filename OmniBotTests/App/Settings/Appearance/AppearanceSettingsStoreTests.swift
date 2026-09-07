import Foundation
import Testing
@testable import Via_Vera

@Suite("Appearance settings persistence")
struct AppearanceSettingsStoreTests {
    @Test("Imports background image data from the photo picker")
    func importsBackgroundPhotoData() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppearanceSettingsStorePhotoTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AppearanceSettingsStore(directoryURL: root)
        let pngData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))

        let importedData = try await store.replaceBackgroundImage(with: pngData)
        let state = try await store.load()

        #expect(importedData == pngData)
        #expect(state.backgroundImageData == pngData)
    }

    @Test("Preferences and background image survive reload and removal")
    func persistsAppearanceState() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppearanceSettingsStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AppearanceSettingsStore(
            directoryURL: root.appending(path: "appearance", directoryHint: .isDirectory)
        )
        let initialState = try await store.load()
        #expect(initialState.preferences == .defaultValue)
        #expect(initialState.backgroundImageData == nil)

        try await store.save(
            AppearancePreferences(
                themeMode: .dark,
                backgroundOpacity: 2,
                backgroundBrightness: -2,
                backgroundBlur: 80
            )
        )

        let pngData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let sourceURL = root.appending(path: "background.png", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try pngData.write(to: sourceURL, options: .atomic)

        let importedData = try await store.replaceBackgroundImage(from: sourceURL)
        #expect(importedData == pngData)

        let reloadedState = try await store.load()
        #expect(reloadedState.preferences.themeMode == .dark)
        #expect(reloadedState.preferences.backgroundOpacity == 1)
        #expect(reloadedState.preferences.backgroundBrightness == -0.5)
        #expect(reloadedState.preferences.backgroundBlur == 30)
        #expect(reloadedState.backgroundImageData == pngData)

        try await store.removeBackgroundImage()
        let stateAfterRemoval = try await store.load()
        #expect(stateAfterRemoval.backgroundImageData == nil)
        #expect(stateAfterRemoval.preferences == reloadedState.preferences)
    }

    @Test("Existing appearance settings default to the system theme without losing adjustments")
    func loadsLegacyPreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppearanceSettingsLegacyTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacyData = Data("""
            {"backgroundOpacity":0.65,"backgroundBrightness":-0.2,"backgroundBlur":14}
            """.utf8)
        try legacyData.write(to: root.appending(path: "appearance.json"))

        let store = AppearanceSettingsStore(directoryURL: root)
        let state = try await store.load()

        #expect(state.preferences.themeMode == .system)
        #expect(state.preferences.backgroundOpacity == 0.65)
        #expect(state.preferences.backgroundBrightness == -0.2)
        #expect(state.preferences.backgroundBlur == 14)

        try await store.save(state.preferences)
        let reloadedState = try await store.load()
        #expect(reloadedState.preferences == state.preferences)
    }

    @Test("Theme changes survive model reload, including returning to the system theme")
    @MainActor
    func persistsThemeChangesThroughModel() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppearanceSettingsThemeTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppearanceSettingsModel(store: AppearanceSettingsStore(directoryURL: root))
        await model.load()
        #expect(model.themeMode == .system)
        model.backgroundOpacity = 0.65
        model.backgroundBrightness = -0.2
        model.backgroundBlur = 14

        for mode in [AppearanceThemeMode.dark, .light, .system] {
            model.themeMode = mode
            await model.save(model.preferences)
            #expect(model.errorMessage == nil)

            let reloadedModel = AppearanceSettingsModel(
                store: AppearanceSettingsStore(directoryURL: root)
            )
            await reloadedModel.load()

            #expect(reloadedModel.errorMessage == nil)
            #expect(reloadedModel.themeMode == mode)
            #expect(reloadedModel.preferences == model.preferences)
            #expect(reloadedModel.backgroundOpacity == 0.65)
            #expect(reloadedModel.backgroundBrightness == -0.2)
            #expect(reloadedModel.backgroundBlur == 14)
        }
    }
}
