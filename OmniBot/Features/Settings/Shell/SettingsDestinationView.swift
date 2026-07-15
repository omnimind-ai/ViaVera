import SwiftUI

struct SettingsDestinationView: View {
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
        switch destination {
        case .providers:
            ProviderSettingsView()
        case .soul:
            SoulSettingsView()
        case .memory:
            MemorySettingsView()
        case .skills:
            SkillSettingsView()
#if os(iOS)
        case .permissions:
            IOSPermissionSettingsView()
#endif
        case .appearance:
            AppearanceSettingsView()
        case .workspace:
            WorkspaceBrowserView(onSelectBreadcrumbPath: onSelectWorkspacePath)
        case .runtime:
            AlpineRuntimeView()
        }
    }
}
