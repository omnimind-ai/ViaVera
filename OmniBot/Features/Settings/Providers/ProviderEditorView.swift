import SwiftUI

struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    let route: ProviderSettingsRoute

    @State private var providerID: String?
    @State private var isPreparing = true
    @State private var showDeleteConfirmation = false
    @State private var isDeletingProvider = false
    @State private var selectedModelRoute: ProviderModelEditorRoute?
    @State private var autoSaver = DebouncedAutoSaver<ProviderEditorState>(
        delay: AppDesign.settingsAutoSaveDelay
    )

    init(route: ProviderSettingsRoute) {
        self.route = route
        _providerID = State(initialValue: route.providerID)
    }

    var body: some View {
        @Bindable var settings = appModel.providerSettings

        SettingsPageLayout(title: pageTitle) {
            Button(
                "删除当前服务商",
                systemImage: "trash",
                role: .destructive,
                action: requestDelete
            )
            .disabled(!isReady || isDeletingProvider)
            .confirmationDialog(
                "删除当前模型服务？",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除模型服务", role: .destructive, action: deleteProvider)
                Button("取消", role: .cancel) { }
            } message: {
                Text("对应的 API Key 也会从系统钥匙串中删除。")
            }
        } content: {
            if isPreparing {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("正在载入服务商…")
                        Spacer()
                    }
                    .frame(minHeight: 96)
                }
            } else if isReady {
                SettingsInputField("服务商名称") {
                    TextField("请输入服务商名称", text: $settings.editor.name)
                        .settingsInputStyle()
                        .accessibilityLabel("服务商名称")
                }

                SettingsInputField("Base URL") {
                    TextField("https://api.example.com/v1", text: $settings.editor.baseURL)
                        .autocorrectionDisabled()
                        .settingsInputStyle()
                        .accessibilityLabel("Base URL")
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                }

                SettingsInputField(
                    "API Key",
                    footer: "保存在系统钥匙串"
                ) {
                    ProviderAPIKeyField(apiKey: $settings.editor.apiKey)
                }

                Section {
                    Picker(
                        "协议",
                        selection: Binding(
                            get: { settings.editor.protocolType },
                            set: { protocolType in
                                settings.editor.protocolType = protocolType
                                if !protocolType.supportedWireAPIs.contains(
                                    settings.editor.wireAPI
                                ) {
                                    settings.editor.wireAPI = .chatCompletions
                                }
                            }
                        )
                    ) {
                        ForEach(ProviderProtocolType.allCases, id: \.self) { protocolType in
                            Text(protocolType.displayName).tag(protocolType)
                        }
                    }

                    if settings.editor.protocolType == .openAICompatible {
                        Picker("接口", selection: $settings.editor.wireAPI) {
                            ForEach(settings.editor.protocolType.supportedWireAPIs, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    } else {
                        LabeledContent(
                            "接口",
                            value: settings.editor.protocolType.interfaceDisplayName
                        )
                    }
                }

                ProviderModelListSection(
                    models: settings.editor.models,
                    isRefreshing: settings.isRefreshingModels,
                    refresh: refreshModels,
                    addCustom: addCustomModel,
                    open: openModel,
                    toggleVisibility: settings.toggleModelVisibility,
                    delete: settings.deleteModel
                )

                if let modelRefreshNotice = settings.modelRefreshNotice {
                    Section {
                        Label(modelRefreshNotice, systemImage: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = settings.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("无法打开服务商", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(settings.errorMessage ?? "该服务商可能已被删除。")
                    }
                    .frame(minHeight: 120)
                }
            }
        }
#if os(macOS)
        .navigationBarBackButtonHidden()
#endif
        .task(id: route) {
            await prepareEditor()
        }
        .onDisappear(perform: flushPendingChanges)
        .onChange(of: settings.editor) { _, editor in
            autoSaver.submit(editor)
        }
        .sheet(item: $selectedModelRoute) { route in
            ProviderModelEditorView(route: route, onSave: saveModel)
        }
    }

    private var isReady: Bool {
        guard let providerID else { return false }
        return !isPreparing && appModel.providerSettings.editor.id == providerID
    }

    private var pageTitle: String {
        if isReady {
            let name = appModel.providerSettings.editor.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "未命名服务商" : name
        }

        if let providerID,
           let profile = appModel.providerSettings.profiles.first(where: { $0.id == providerID }) {
            return profile.name
        }
        return route == .create ? "新服务商" : "模型服务"
    }

    private func prepareEditor() async {
        isPreparing = true
        switch route {
        case .create:
            await appModel.providerSettings.createProfile()
            let editorID = appModel.providerSettings.editor.id
            if appModel.providerSettings.profiles.contains(where: { $0.id == editorID }) {
                providerID = editorID
            } else {
                providerID = nil
            }
        case let .edit(providerID):
            await appModel.providerSettings.edit(providerID)
            if appModel.providerSettings.editor.id == providerID {
                self.providerID = providerID
            } else {
                self.providerID = nil
            }
        }
        isPreparing = false
        guard isReady else { return }

        let settings = appModel.providerSettings
        autoSaver.configure(lastSavedValue: settings.editor) { [weak settings] state in
            guard let settings else { return nil }
            await settings.save(state)
            guard settings.errorMessage == nil else { return nil }

            return state
        }
    }

    private func refreshModels() {
        let state = appModel.providerSettings.editor
        Task {
            await appModel.providerSettings.refreshModels(state)
        }
    }

    private func addCustomModel() {
        selectedModelRoute = .custom()
    }

    private func openModel(_ model: ModelOption) {
        selectedModelRoute = .existing(model)
    }

    private func saveModel(_ model: ModelOption, originalID: String?) -> Bool {
        appModel.providerSettings.upsertModel(model, replacing: originalID)
    }

    private func flushPendingChanges() {
        guard isReady else { return }
        autoSaver.flush(appModel.providerSettings.editor)
    }

    private func requestDelete() {
        showDeleteConfirmation = true
    }

    private func deleteProvider() {
        guard let providerID, !isDeletingProvider else { return }
        isDeletingProvider = true
        Task {
            await appModel.providerSettings.delete(providerID)
            if !appModel.providerSettings.profiles.contains(where: { $0.id == providerID }) {
                dismiss()
            } else {
                isDeletingProvider = false
            }
        }
    }
}
