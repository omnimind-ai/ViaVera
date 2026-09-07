import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selection: SettingsCardDestination?

    var body: some View {
        List(selection: $selection) {
            Section("模型") {
                SettingsCardRow(destination: .providers)
                    .tag(SettingsCardDestination.providers)
                SettingsCardRow(destination: .usage)
                    .tag(SettingsCardDestination.usage)
            }

            Section("Agent") {
                SettingsCardRow(destination: .soul)
                    .tag(SettingsCardDestination.soul)
                SettingsCardRow(destination: .memory)
                    .tag(SettingsCardDestination.memory)
                SettingsCardRow(destination: .skills)
                    .tag(SettingsCardDestination.skills)
            }

            Section("系统") {
                SettingsCardRow(destination: .permissions)
                    .tag(SettingsCardDestination.permissions)
                SettingsCardRow(destination: .appearance)
                    .tag(SettingsCardDestination.appearance)
                SettingsCardRow(destination: .workspace)
                    .tag(SettingsCardDestination.workspace)
                SettingsCardRow(destination: .runtime)
                    .tag(SettingsCardDestination.runtime)
            }
        }
        .listStyle(.sidebar)
#if os(macOS)
        .scrollContentBackground(.hidden)
        .background(.background)
        .frame(width: AppDesign.settingsSidebarMaximumWidth)
#endif
    }
}
