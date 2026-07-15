import SwiftUI

struct SettingsNavigationListView: View {
    var body: some View {
        List {
            Section("模型") {
                NavigationLink(value: SettingsCardDestination.providers) {
                    SettingsCardRow(destination: .providers)
                }
            }

            Section("Agent") {
                NavigationLink(value: SettingsCardDestination.soul) {
                    SettingsCardRow(destination: .soul)
                }
                NavigationLink(value: SettingsCardDestination.memory) {
                    SettingsCardRow(destination: .memory)
                }
                NavigationLink(value: SettingsCardDestination.skills) {
                    SettingsCardRow(destination: .skills)
                }
            }

            Section("系统") {
#if os(iOS)
                NavigationLink(value: SettingsCardDestination.permissions) {
                    SettingsCardRow(destination: .permissions)
                }
#endif
                NavigationLink(value: SettingsCardDestination.appearance) {
                    SettingsCardRow(destination: .appearance)
                }
                NavigationLink(value: SettingsCardDestination.workspace) {
                    SettingsCardRow(destination: .workspace)
                }
                NavigationLink(value: SettingsCardDestination.runtime) {
                    SettingsCardRow(destination: .runtime)
                }
            }
        }
#if os(macOS)
        .listStyle(.inset)
#else
        .listStyle(.insetGrouped)
#endif
    }
}
