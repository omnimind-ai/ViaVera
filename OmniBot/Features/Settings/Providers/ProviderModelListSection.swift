import SwiftUI

struct ProviderModelListSection: View {
    let models: [ModelOption]
    let isRefreshing: Bool
    let refresh: () -> Void
    let addCustom: () -> Void
    let open: (ModelOption) -> Void
    let toggleVisibility: (String) -> Void
    let delete: (String) -> Void

    var body: some View {
        Section {
            if models.isEmpty {
                Color.clear
                    .frame(minHeight: 120)
                    .accessibilityHidden(true)
            } else {
                ForEach(models) { model in
                    ProviderModelRow(
                        model: model,
                        open: { open(model) },
                        toggleVisibility: { toggleVisibility(model.id) },
                        delete: { delete(model.id) }
                    )
                }
            }

            Button("添加自定义模型", systemImage: "plus", action: addCustom)
        } header: {
            HStack {
                Text("模型")
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在获取模型")
                } else {
                    Button("刷新", action: refresh)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
            }
        }
    }
}
