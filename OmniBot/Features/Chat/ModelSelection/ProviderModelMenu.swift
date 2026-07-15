import SwiftUI

struct ProviderModelMenu: View {
    @Environment(AppModel.self) private var appModel
#if !os(macOS)
    @State private var isShowingProviderSettings = false
#endif

    let conversation: ConversationRecord
    let isDisabled: Bool

    var body: some View {
        Menu {
            if selectableProfiles.isEmpty, !currentAvailability.needsCurrentEntry {
                Button("还没有可用模型") { }
                    .disabled(true)
            } else {
                Picker("模型", selection: modelSelection) {
                    if currentAvailability.needsCurrentEntry {
                        Section {
                            Label {
                                Text(
                                    "\(selectedModelName)（当前 · \(currentUnavailableReason)）"
                                )
                            } icon: {
                                ModelVendorIcon(
                                    model: selectedModel,
                                    provider: selectedProvider
                                )
                            }
                            .tag(currentSelection)
                            .disabled(true)
                        } header: {
                            Label {
                                Text("当前 · \(selectedProviderName)")
                            } icon: {
                                ModelVendorIcon(
                                    model: selectedModel,
                                    provider: selectedProvider
                                )
                            }
                        }
                    }

                    ForEach(selectableProfiles) { provider in
                        Section {
                            ForEach(visibleModels(for: provider)) { model in
                                Label {
                                    Text(model.displayName)
                                } icon: {
                                    ModelVendorIcon(model: model, provider: provider)
                                }
                                .tag(
                                    ProviderModelSelection(
                                        providerID: provider.id,
                                        modelID: model.id
                                    )
                                )
                            }
                        } header: {
                            Label {
                                Text(provider.name)
                            } icon: {
                                ModelVendorIcon(
                                    model: visibleModels(for: provider).first,
                                    provider: provider
                                )
                            }
                        }
                    }
                }
                .pickerStyle(.inline)
            }

            Divider()

            Button(
                "配置模型服务",
                systemImage: "gearshape",
                action: showProviderSettings
            )
        } label: {
#if os(macOS)
            HStack(spacing: 6) {
                ModelVendorIcon(
                    model: selectedModel,
                    provider: selectedProvider,
                    size: AppDesign.composerIconSize,
                    forceMonochrome: true
                )
                Text(selectedModelName)
            }
            .font(AppDesign.composerControlFont)
            .lineLimit(1)
#else
            ModelVendorIcon(
                model: selectedModel,
                provider: selectedProvider,
                size: AppDesign.composerIconSize,
                forceMonochrome: true
            )
#endif
        }
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
#if os(macOS)
        .frame(maxWidth: AppDesign.composerModelControlMaximumWidth)
        .frame(height: AppDesign.composerControlSize)
#else
        .composerControlFrame()
#endif
        .buttonStyle(.borderless)
        .disabled(isDisabled || appModel.chatCoordinator.busyConversationID != nil)
        .accessibilityLabel("当前模型：\(selectedModelName)")
        .accessibilityHint("选择模型或打开模型配置")
#if !os(macOS)
        .sheet(isPresented: $isShowingProviderSettings) {
            SettingsCardView(initialDestination: .providers)
        }
#endif
    }

    private var enabledProfiles: [ProviderProfile] {
        appModel.providerSettings.profiles.filter(\.isEnabled)
    }

    private var selectableProfiles: [ProviderProfile] {
        enabledProfiles.filter { !visibleModels(for: $0).isEmpty }
    }

    private func visibleModels(for provider: ProviderProfile) -> [ModelOption] {
        provider.models.filter { !$0.isHidden }
    }

    private var currentSelection: ProviderModelSelection {
        ProviderModelSelection(
            providerID: conversation.providerID ?? "",
            modelID: conversation.modelID
        )
    }

    private var currentAvailability: ProviderModelSelectionAvailability {
        currentSelection.availability(in: appModel.providerSettings.profiles)
    }

    private var currentUnavailableReason: String {
        switch currentAvailability {
        case .providerMissing:
            "服务商不可用"
        case .providerDisabled:
            "服务商已停用"
        case .modelMissing:
            "模型不可用"
        case .modelHidden:
            "模型已隐藏"
        case .none, .available:
            "当前"
        }
    }

    private var selectedModelName: String {
        guard let selectedProvider else {
            return conversation.modelID.isEmpty ? "选择模型" : conversation.modelID
        }

        return selectedProvider.models.first(where: { $0.id == conversation.modelID })?.displayName
            ?? (conversation.modelID.isEmpty ? "选择模型" : conversation.modelID)
    }

    private var selectedProvider: ProviderProfile? {
        appModel.providerSettings.profiles.first { $0.id == conversation.providerID }
    }

    private var selectedProviderName: String {
        if let name = selectedProvider?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let storedProviderID = conversation.providerID {
            let providerID = storedProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !providerID.isEmpty {
                return providerID
            }
        }
        return "未知服务商"
    }

    private var selectedModel: ModelOption? {
        selectedProvider?.models.first { $0.id == conversation.modelID }
    }

    private var modelSelection: Binding<ProviderModelSelection> {
        Binding(
            get: { currentSelection },
            set: { selection in
                appModel.selectModel(
                    providerID: selection.providerID,
                    modelID: selection.modelID,
                    for: conversation
                )
            }
        )
    }

    private func showProviderSettings() {
#if os(macOS)
        appModel.presentSettings(.providers)
#else
        isShowingProviderSettings = true
#endif
    }
}
