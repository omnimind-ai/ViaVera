import SwiftUI

struct AlpineRuntimeView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.alpineEnvironmentSettings

        SettingsPageLayout(
            title: "Alpine Linux",
            actions: {
                Button("重新检测", systemImage: "arrow.clockwise", action: refreshInventory)
                    .disabled(settings.isBusy)
            }
        ) {
            Section("环境配置") {
                if settings.operation == .detecting {
                    ProgressView("正在检测 Alpine 开发环境…")
                } else {
                    Text(
                        "已就绪 \(settings.readyCount)/\(AlpineEnvironmentPackageDefinition.all.count) 项。"
                            + "缺失组件会被默认选中，可一键安装并自动复检。"
                    )
                        .foregroundStyle(.secondary)
                }

                Button(installButtonTitle, action: installSelectedPackages)
                    .buttonStyle(.borderedProminent)
                    .disabled(settings.isBusy || settings.selectedMissingCount == 0)

                if settings.operation == .installing {
                    ProgressView("正在安装并配置所选组件…")
                }

                if let feedbackMessage = settings.feedbackMessage {
                    Label(
                        feedbackMessage,
                        systemImage: settings.feedbackIsError
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(settings.feedbackIsError ? .red : .secondary)
                }
            }

            ForEach(AlpineEnvironmentPackageDefinition.groupTitles, id: \.self) { groupTitle in
                Section(groupTitle) {
                    ForEach(packages(in: groupTitle)) { definition in
                        AlpineEnvironmentPackageRow(
                            definition: definition,
                            inventoryItem: settings.inventory[definition.id],
                            isSelected: settings.selectedPackageIDs.contains(definition.id),
                            isDetecting: settings.operation == .detecting,
                            isDisabled: settings.isBusy,
                            toggleSelection: {
                                settings.togglePackageSelection(definition.id)
                            }
                        )
                    }
                }
            }

            Section("Alpine 软件源") {
                Picker("软件源", selection: $settings.selectedMirror) {
                    ForEach(AlpinePackageMirror.allCases) { mirror in
                        Text(mirror.title)
                            .tag(mirror)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(settings.isBusy)
                .onChange(of: settings.selectedMirror) { _, _ in
                    applySelectedMirror()
                }

                if settings.operation == .applyingMirror {
                    ProgressView("正在应用软件源…")
                }
            }

            AlpineRootFileSystemSection(manager: appModel.alpineRootFileSystem)
        }
        .task {
            if !settings.hasCompletedDetection {
                await settings.refreshInventory(selectMissingByDefault: true)
            }
            await appModel.alpineRootFileSystem.refreshSize()
        }
    }

    private var installButtonTitle: String {
        let settings = appModel.alpineEnvironmentSettings
        return if settings.operation == .installing {
            "正在安装配置…"
        } else if settings.selectedMissingCount == 0 {
            settings.allPackagesAreReady ? "全部已就绪" : "请选择需要安装的组件"
        } else {
            "一键安装配置（\(settings.selectedMissingCount) 项）"
        }
    }

    private func packages(in groupTitle: String) -> [AlpineEnvironmentPackageDefinition] {
        AlpineEnvironmentPackageDefinition.all.filter { $0.groupTitle == groupTitle }
    }

    private func refreshInventory() {
        Task {
            await appModel.alpineEnvironmentSettings.refreshInventory()
        }
    }

    private func installSelectedPackages() {
        Task {
            await appModel.alpineEnvironmentSettings.installSelectedPackages()
            await appModel.alpineRootFileSystem.refreshSize()
        }
    }

    private func applySelectedMirror() {
        Task {
            await appModel.alpineEnvironmentSettings.applySelectedMirror()
        }
    }
}
