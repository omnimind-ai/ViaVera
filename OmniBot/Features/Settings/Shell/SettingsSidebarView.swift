import SwiftUI

struct SettingsSidebarView: View {
    @Environment(AppModel.self) private var appModel
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
                if appModel.conversationMode == .task {
                    SettingsCardRow(destination: .skills)
                        .tag(SettingsCardDestination.skills)
                }
            }

            Section("系统") {
                SettingsCardRow(destination: .sync)
                    .tag(SettingsCardDestination.sync)
                if appModel.conversationMode == .task {
                    SettingsCardRow(destination: .permissions)
                        .tag(SettingsCardDestination.permissions)
                }
                SettingsCardRow(destination: .appearance)
                    .tag(SettingsCardDestination.appearance)
#if os(macOS)
                SettingsCardRow(destination: .keyboardShortcuts)
                    .tag(SettingsCardDestination.keyboardShortcuts)
#endif
                if appModel.conversationMode == .task {
                    SettingsCardRow(destination: .workspace)
                        .tag(SettingsCardDestination.workspace)
                    SettingsCardRow(destination: .runtime)
                        .tag(SettingsCardDestination.runtime)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: appModel.conversationMode, initial: true) { _, mode in
            if mode == .chat, selection?.isTaskOnly == true {
                selection = .soul
            }
        }
#if os(macOS)
        .scrollContentBackground(.hidden)
        .background(.background)
        .frame(width: AppDesign.settingsSidebarMaximumWidth)
#endif
    }
}
