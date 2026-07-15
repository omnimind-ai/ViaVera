import SwiftUI

struct IOSPermissionSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = IOSPermissionSettingsModel(
        authorizationClient: ApplePermissionAuthorizationClient(),
        permissionStore: AgentPermissionStore()
    )

    var body: some View {
        @Bindable var model = model

        SettingsPageLayout(title: "权限") {
            Button(
                "刷新",
                systemImage: "arrow.clockwise",
                action: refresh
            )
            .disabled(model.isRefreshing || model.requestingPermission != nil)
        } content: {
            Section {
                ForEach(model.permissions) { permission in
                    IOSPermissionSettingsRow(
                        permission: permission,
                        isDisabled: !model.hasLoaded
                            || model.isRefreshing
                            || model.requestingPermission != nil,
                        setEnabled: { enabled in
                            update(enabled, for: permission)
                        }
                    )
                }
            } header: {
                Text("Agent 权限")
            } footer: {
                Text("开关控制 Agent 能否调用对应工具。关闭不会撤销系统权限；再次打开时，如有需要会显示系统授权页面。")
            }
        }
        .task {
            await model.refresh()
        }
        .onChange(of: scenePhase, scenePhaseDidChange)
        .alert(item: $model.alert) { alert in
            if alert.offersSystemSettings {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("前往设置"), action: openSystemSettings),
                    secondaryButton: .cancel()
                )
            } else {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message)
                )
            }
        }
    }

    private func refresh() {
        Task {
            await model.refresh()
        }
    }

    private func update(
        _ enabled: Bool,
        for permission: IOSPermissionToggleState
    ) {
        Task {
            await model.setEnabled(enabled, for: permission)
        }
    }

    private func openSystemSettings() {
#if os(iOS)
        let settingsURL = URL(string: UIApplication.openSettingsURLString)
#else
        let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security"
        )
#endif
        guard let settingsURL else { return }
        openURL(settingsURL)
    }

    private func scenePhaseDidChange(
        _ oldPhase: ScenePhase,
        _ newPhase: ScenePhase
    ) {
        _ = oldPhase
        guard newPhase == .active else { return }
        refresh()
    }
}
