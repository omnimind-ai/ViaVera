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
        #expect(reloadedState.preferences.backgroundOpacity == 1)
        #expect(reloadedState.preferences.backgroundBrightness == -0.5)
        #expect(reloadedState.preferences.backgroundBlur == 30)
        #expect(reloadedState.backgroundImageData == pngData)

        try await store.removeBackgroundImage()
        let stateAfterRemoval = try await store.load()
        #expect(stateAfterRemoval.backgroundImageData == nil)
    }
}
