import SwiftUI

struct SettingsDestinationView: View {
    @Environment(AppModel.self) private var appModel
    @State private var editingToken = UUID().uuidString
    let destination: SettingsCardDestination
    let onSelectWorkspacePath: (WorkspaceBrowserPath, WorkspaceBrowserPath) -> Void

    init(
        destination: SettingsCardDestination,
        onSelectWorkspacePath: @escaping (
            WorkspaceBrowserPath,
            WorkspaceBrowserPath
        ) -> Void = { _, _ in }
    ) {
        self.destination = destination
        self.onSelectWorkspacePath = onSelectWorkspacePath
    }

    var body: some View {
        destinationContent
            .onAppear { if destination != .sync { appModel.cloudSync.editingSettings.insert(editingToken) } }
            .onDisappear {
                appModel.cloudSync.editingSettings.remove(editingToken)
                appModel.cloudSync.requestSync()
            }
    }

    @ViewBuilder private var destinationContent: some View {
        switch destination {
        case .providers:
            ProviderSettingsView()
        case .usage:
            ModelUsageView()
        case .soul:
            SoulSettingsView()
        case .memory:
            MemorySettingsView()
        case .skills:
            SkillSettingsView()
        case .permissions:
            IOSPermissionSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .sync:
            CloudSyncSettingsView()
        case .workspace:
            WorkspaceBrowserView(onSelectBreadcrumbPath: onSelectWorkspacePath)
        case .runtime:
            AlpineRuntimeView()
        }
    }
}
