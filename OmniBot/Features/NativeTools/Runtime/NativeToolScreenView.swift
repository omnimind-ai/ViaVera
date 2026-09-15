import SwiftUI

struct NativeToolScreenView: View {
    @Bindable var runtime: NativeToolRuntime
    @State private var alert: NativeToolAlert?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if runtime.record.package.screens.count > 1 {
                    Picker("页面", selection: $runtime.screenID) {
                        ForEach(runtime.record.package.screens) { screen in Text(screen.title).tag(screen.id) }
                    }
                    .pickerStyle(.menu)
                }
                ForEach(runtime.screen.components) { component in
                    NativeToolComponentView(component: component, runtime: runtime)
                }
                if runtime.persistenceFailed {
                    Label("更改尚未保存，请从工具菜单重新载入。", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .disabled(runtime.persistenceFailed)
        }
        .alert(item: $alert) { alert in
            Alert(title: Text("操作未完成"), message: Text(alert.message), dismissButton: .default(Text("好")) {
                runtime.errorMessage = nil
            })
        }
        .onChange(of: runtime.errorMessage) { _, message in
            if let message { alert = NativeToolAlert(message) }
        }
    }
}
