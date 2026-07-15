import SwiftUI

struct ProviderModelEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (ModelOption, String?) -> Bool

    @State private var state: ProviderModelEditorState

    init(
        route: ProviderModelEditorRoute,
        onSave: @escaping (ModelOption, String?) -> Bool
    ) {
        self.onSave = onSave
        _state = State(initialValue: ProviderModelEditorState(model: route.model))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标识") {
                    TextField("模型 ID", text: $state.modelID)
                        .autocorrectionDisabled()
                        .disabled(state.originalID != nil)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif

                    TextField("显示名称", text: $state.displayName)
                    TextField("AI 服务商", text: $state.providerName)
                }

                Section("功能特性") {
                    TextField(
                        "上下文窗口",
                        value: $state.contextWindow,
                        format: .number
                    )
#if os(iOS)
                    .keyboardType(.numberPad)
#endif

                    TextField(
                        "最大输出 Token 数",
                        value: $state.maxOutputTokens,
                        format: .number
                    )
#if os(iOS)
                    .keyboardType(.numberPad)
#endif

                    Toggle("支持工具调用", isOn: $state.supportsTools)
                    Toggle("支持深度思考", isOn: $state.supportsReasoning)
                }

                Section {
                    Toggle("隐藏", isOn: $state.isHidden)
                } footer: {
                    Text("隐藏的模型不会出现在模型选择器中。")
                }

                Section("输入模态") {
                    Toggle("图片输入", isOn: $state.supportsImage)
                    Toggle("PDF 输入", isOn: $state.supportsPDF)
                    Toggle("音频输入", isOn: $state.supportsAudio)
                    Toggle("视频输入", isOn: $state.supportsVideo)
                }

                Section("说明") {
                    TextField("模型说明（可选）", text: $state.description, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let modelsDevProviderID = state.modelsDevProviderID {
                    Section {
                        LabeledContent("models.dev", value: modelsDevProviderID)
                    } header: {
                        Text("数据来源")
                    } footer: {
                        Text("保存后将使用当前页面的自定义值，后续刷新不会覆盖。")
                    }
                }
            }
            .settingsFormStyle()
            .navigationTitle(state.originalID == nil ? "添加自定义模型" : "模型详情")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        guard onSave(state.modelOption, state.originalID) else { return }
        dismiss()
    }
}
