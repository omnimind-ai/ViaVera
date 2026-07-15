import SwiftUI
#if os(iOS)
import PhotosUI
#else
import UniformTypeIdentifiers
#endif

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var appModel
#if os(iOS)
    @State private var selectedBackgroundPhoto: PhotosPickerItem?
#else
    @State private var isImportingBackground = false
#endif
    @State private var lastPersistedPreferences: AppearancePreferences?

    var body: some View {
        @Bindable var settings = appModel.appearanceSettings
        let preferences = settings.preferences
        let backgroundSelectionTitle = settings.hasBackgroundImage
            ? "更换背景图片"
            : "选择背景图片"

        SettingsPageLayout(title: "外观") {
            Section {
#if os(iOS)
                PhotosPicker(
                    selection: $selectedBackgroundPhoto,
                    matching: .images,
                    preferredItemEncoding: .current
                ) {
                    Label(
                        backgroundSelectionTitle,
                        systemImage: "photo"
                    )
                }
#else
                Button(
                    backgroundSelectionTitle,
                    systemImage: "photo",
                    action: presentBackgroundImporter
                )
#endif

                if settings.hasBackgroundImage {
                    Button(
                        "移除背景图片",
                        systemImage: "trash",
                        role: .destructive,
                        action: removeBackgroundImage
                    )
                }
            } header: {
                Text("聊天背景")
            } footer: {
                Text("图片只保存在本机，并应用到聊天页面背景。")
            }

            Section("显示效果") {
                AppearanceAdjustmentRow(
                    title: "透明度",
                    valueText: settings.backgroundOpacity.formatted(
                        .percent.precision(.fractionLength(0))
                    ),
                    value: $settings.backgroundOpacity,
                    range: AppearancePreferences.opacityRange,
                    step: 0.01
                )

                AppearanceAdjustmentRow(
                    title: "亮度",
                    valueText: settings.backgroundBrightness.formatted(
                        .percent.precision(.fractionLength(0))
                    ),
                    value: $settings.backgroundBrightness,
                    range: AppearancePreferences.brightnessRange,
                    step: 0.01
                )

                AppearanceAdjustmentRow(
                    title: "磨砂感",
                    valueText: "\(settings.backgroundBlur.formatted(.number.precision(.fractionLength(0)))) 点",
                    value: $settings.backgroundBlur,
                    range: AppearancePreferences.blurRange,
                    step: 1
                )
            }
            .disabled(!settings.hasBackgroundImage)

            if let errorMessage = settings.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
#if os(macOS)
        .fileImporter(
            isPresented: $isImportingBackground,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: importBackground
        )
#endif
#if os(iOS)
        .onChange(of: selectedBackgroundPhoto) { _, photo in
            guard let photo else { return }
            importBackground(photo)
        }
#endif
        .task {
            lastPersistedPreferences = preferences
        }
        .task(id: preferences) {
            await autoSave(preferences)
        }
        .onDisappear(perform: savePendingChanges)
    }

#if os(macOS)
    private func presentBackgroundImporter() {
        isImportingBackground = true
    }

    private func importBackground(_ result: Result<[URL], any Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                await appModel.appearanceSettings.replaceBackgroundImage(from: url)
            } catch {
                appModel.appearanceSettings.errorMessage = error.localizedDescription
            }
        }
    }
#endif

#if os(iOS)
    private func importBackground(_ photo: PhotosPickerItem) {
        Task {
            defer { selectedBackgroundPhoto = nil }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else {
                    throw AppearanceSettingsStoreError.invalidImage
                }
                await appModel.appearanceSettings.replaceBackgroundImage(with: data)
            } catch {
                appModel.appearanceSettings.errorMessage = error.localizedDescription
            }
        }
    }
#endif

    private func removeBackgroundImage() {
        Task {
            await appModel.appearanceSettings.removeBackgroundImage()
        }
    }

    private func autoSave(_ preferences: AppearancePreferences) async {
        guard let lastPersistedPreferences,
              preferences != lastPersistedPreferences else {
            return
        }

        do {
            try await Task.sleep(for: AppDesign.settingsAutoSaveDelay)
        } catch {
            return
        }

        guard !Task.isCancelled,
              appModel.appearanceSettings.preferences == preferences else {
            return
        }

        await appModel.appearanceSettings.save(preferences)
        guard !Task.isCancelled,
              appModel.appearanceSettings.errorMessage == nil else {
            return
        }
        self.lastPersistedPreferences = appModel.appearanceSettings.preferences
    }

    private func savePendingChanges() {
        guard let lastPersistedPreferences else { return }
        let preferences = appModel.appearanceSettings.preferences
        guard preferences != lastPersistedPreferences else { return }

        Task {
            await appModel.appearanceSettings.save(preferences)
        }
    }
}
