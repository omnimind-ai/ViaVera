import SwiftUI

struct SettingsCardView: View {
    @Environment(\.dismiss) private var dismiss
#if !os(macOS)
    @Environment(AppModel.self) private var appModel
#endif
    @State private var selection: SettingsCardDestination?
    @State private var path: NavigationPath

    init(initialDestination: SettingsCardDestination? = nil) {
        _selection = State(initialValue: initialDestination ?? .providers)
        var initialPath = NavigationPath()
        if let initialDestination {
            initialPath.append(initialDestination)
        }
        _path = State(initialValue: initialPath)
    }

    var body: some View {
#if os(macOS)
        HStack(spacing: 0) {
            SettingsSidebarView(selection: $selection)

            Divider()

            NavigationStack {
                if let selection {
                    SettingsDestinationView(destination: selection)
                } else {
                    ContentUnavailableView("选择设置项目", systemImage: "gearshape")
                }
            }
            .id(selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
        NavigationStack(path: $path) {
            SettingsNavigationListView()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: closeSettings)
                }
            }
            .navigationDestination(for: SettingsCardDestination.self) { destination in
                SettingsDestinationView(
                    destination: destination,
                    onSelectWorkspacePath: selectWorkspacePath
                )
            }
        }
        // The sheet owns its presentation appearance independently of the main window.
        .preferredColorScheme(appModel.appearanceSettings.themeMode.colorScheme)
#endif
    }

    private func closeSettings() {
        dismiss()
    }

    private func selectWorkspacePath(
        _ targetPath: WorkspaceBrowserPath,
        from currentPath: WorkspaceBrowserPath
    ) {
        guard targetPath.components.count < currentPath.components.count,
              currentPath.components.starts(with: targetPath.components)
        else {
            return
        }

        let levelCount = currentPath.components.count - targetPath.components.count
        guard levelCount <= path.count else { return }
        path.removeLast(levelCount)
    }
}
