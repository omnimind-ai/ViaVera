import SwiftUI

struct ProviderSettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.providerSettings

        SettingsPageLayout(title: "模型服务") {
#if os(iOS)
            EditButton()
                .disabled(settings.profiles.isEmpty || settings.isMutating)

            NavigationLink(value: ProviderSettingsRoute.create) {
                Label("添加模型服务", systemImage: "plus")
            }
            .disabled(settings.isMutating)
#endif
        } content: {
            Section("当前已配置的服务商") {
                if settings.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("还没有模型服务", systemImage: "cpu")
                    } description: {
                        Text("添加服务后即可为 Agent 选择模型。")
                    }
                    .frame(minHeight: 96)
                } else {
                    ForEach(settings.profiles) { profile in
                        NavigationLink(value: ProviderSettingsRoute.edit(profile.id)) {
                            ProviderProfileRow(profile: profile)
                        }
                    }
#if os(iOS)
                    .onDelete(perform: deleteProfiles)
                    .onMove(perform: moveProfiles)
#endif
                }
            }

#if os(macOS)
            Section {
                NavigationLink(value: ProviderSettingsRoute.create) {
                    Label("添加模型服务", systemImage: "plus")
                }
            }
#endif

            if let errorMessage = settings.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .disabled(settings.isMutating)
        .navigationDestination(for: ProviderSettingsRoute.self) { route in
            ProviderEditorView(route: route)
        }
    }

#if os(iOS)
    private func deleteProfiles(at offsets: IndexSet) {
        let providerIDs = offsets.compactMap { index in
            appModel.providerSettings.profiles.indices.contains(index)
                ? appModel.providerSettings.profiles[index].id
                : nil
        }
        Task {
            for providerID in providerIDs {
                await appModel.providerSettings.delete(providerID)
            }
        }
    }

    private func moveProfiles(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        Task {
            await appModel.providerSettings.moveProfiles(
                fromOffsets: offsets,
                toOffset: destination
            )
        }
    }
#endif
}
