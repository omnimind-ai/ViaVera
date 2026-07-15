import Foundation

actor AppearanceSettingsStore {
    private static let maximumConfigurationBytes = 4_096
    private static let maximumImageBytes = 64 * 1_024 * 1_024

    private let directoryURL: URL
    private let configurationURL: URL
    private let backgroundImageURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
        configurationURL = directoryURL.appending(
            path: "appearance.json",
            directoryHint: .notDirectory
        )
        backgroundImageURL = directoryURL.appending(
            path: "chat-background.data",
            directoryHint: .notDirectory
        )
    }

    func load() throws -> AppearanceSettingsState {
        try prepareDirectory()

        let preferences: AppearancePreferences
        if let data = try readBoundedFile(
            at: configurationURL,
            maximumBytes: Self.maximumConfigurationBytes
        ) {
            do {
                preferences = try JSONDecoder()
                    .decode(AppearancePreferences.self, from: data)
                    .normalized
            } catch {
                throw AppearanceSettingsStoreError.corruptedSettings(
                    error.localizedDescription
                )
            }
        } else {
            preferences = .defaultValue
        }

        let backgroundImageData = try readBoundedFile(
            at: backgroundImageURL,
            maximumBytes: Self.maximumImageBytes
        )
        if let backgroundImageData,
           AppearanceBackgroundImageDecoder.decode(backgroundImageData) == nil {
            throw AppearanceSettingsStoreError.invalidImage
        }

        return AppearanceSettingsState(
            preferences: preferences,
            backgroundImageData: backgroundImageData
        )
    }

    func save(_ preferences: AppearancePreferences) throws {
        try prepareDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences.normalized)
        try data.write(to: configurationURL, options: .atomic)
    }

    func replaceBackgroundImage(from sourceURL: URL) throws -> Data {
        try prepareDirectory()
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try sourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true else {
            throw AppearanceSettingsStoreError.invalidImage
        }
        if let fileSize = values.fileSize,
           fileSize > Self.maximumImageBytes {
            throw AppearanceSettingsStoreError.imageTooLarge
        }

        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumImageBytes + 1) ?? Data()
        try persistBackgroundImage(data)
        return data
    }

    func replaceBackgroundImage(with data: Data) throws -> Data {
        try prepareDirectory()
        try persistBackgroundImage(data)
        return data
    }

    func removeBackgroundImage() throws {
        try prepareDirectory()
        guard FileManager.default.fileExists(atPath: backgroundImageURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: backgroundImageURL)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func persistBackgroundImage(_ data: Data) throws {
        guard data.count <= Self.maximumImageBytes else {
            throw AppearanceSettingsStoreError.imageTooLarge
        }
        guard AppearanceBackgroundImageDecoder.decode(data) != nil else {
            throw AppearanceSettingsStoreError.invalidImage
        }
        try data.write(to: backgroundImageURL, options: .atomic)
    }

    private func readBoundedFile(
        at url: URL,
        maximumBytes: Int
    ) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true else {
            throw AppearanceSettingsStoreError.corruptedSettings(
                "保存的数据不是普通文件。"
            )
        }
        if let fileSize = values.fileSize,
           fileSize > maximumBytes {
            if url == backgroundImageURL {
                throw AppearanceSettingsStoreError.imageTooLarge
            }
            throw AppearanceSettingsStoreError.corruptedSettings("保存的数据超过大小限制。")
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            if url == backgroundImageURL {
                throw AppearanceSettingsStoreError.imageTooLarge
            }
            throw AppearanceSettingsStoreError.corruptedSettings("保存的数据超过大小限制。")
        }
        return data
    }
}
