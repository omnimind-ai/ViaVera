import Observation

@MainActor
@Observable
final class IOSPermissionSettingsModel {
    private let authorizationClient: any IOSPermissionAuthorizationClient
    private let permissionStore: AgentPermissionStore

    private(set) var permissions = IOSPermissionKind.allCases.map {
        IOSPermissionToggleState(kind: $0)
    }
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    private(set) var requestingPermission: IOSPermissionKind?
    var alert: IOSPermissionSettingsAlert?

    init(
        authorizationClient: any IOSPermissionAuthorizationClient,
        permissionStore: AgentPermissionStore
    ) {
        self.authorizationClient = authorizationClient
        self.permissionStore = permissionStore
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoaded = true
        }

        let statuses = await authorizationClient.authorizationStatuses()
        let enabledPermissions = await permissionStore.snapshot()

        for permission in permissions {
            let authorization = statuses[permission.kind] ?? .unknown
            let isStoredEnabled = enabledPermissions[permission.kind] ?? false
            permission.authorization = authorization
            permission.isEnabled = effectiveToggleValue(
                storedValue: isStoredEnabled,
                authorization: authorization
            )

            if isStoredEnabled && !permission.isEnabled {
                await permissionStore.setEnabled(false, for: permission.kind)
            }
        }
    }

    func setEnabled(
        _ enabled: Bool,
        for permission: IOSPermissionToggleState
    ) async {
        guard hasLoaded, !isRefreshing else {
            permission.isEnabled = await permissionStore.isEnabled(permission.kind)
            return
        }

        if !enabled {
            permission.isEnabled = false
            await permissionStore.setEnabled(false, for: permission.kind)
            return
        }

        guard requestingPermission == nil else {
            permission.isEnabled = await permissionStore.isEnabled(permission.kind)
            return
        }

        if permission.authorization.allowsAgentAccess {
            await permissionStore.setEnabled(true, for: permission.kind)
            permission.isEnabled = true
            return
        }

        switch permission.authorization {
        case .notDetermined, .writeOnly, .unknown:
            await requestAuthorizationAndEnable(permission)
        case .denied:
            await rejectEnable(
                permission,
                message: "请先在系统设置中允许 Via Vera 访问\(permission.kind.title)。",
                offersSystemSettings: true
            )
        case .restricted:
            await rejectEnable(
                permission,
                message: "此设备限制了\(permission.kind.title)权限，当前无法启用。"
            )
        case .unavailable:
            await rejectEnable(
                permission,
                message: "此设备当前无法使用\(permission.kind.title)权限。"
            )
        case .authorized, .limited, .requested:
            break
        }
    }

    private func requestAuthorizationAndEnable(
        _ permission: IOSPermissionToggleState
    ) async {
        requestingPermission = permission.kind
        defer { requestingPermission = nil }

        do {
            try await authorizationClient.requestAuthorization(for: permission.kind)
            let statuses = await authorizationClient.authorizationStatuses()
            let authorization = statuses[permission.kind] ?? .unknown
            permission.authorization = authorization

            guard authorization.allowsAgentAccess else {
                let offersSystemSettings = authorization == .denied
                    || authorization == .writeOnly
                await rejectEnable(
                    permission,
                    message: denialMessage(
                        for: permission.kind,
                        authorization: authorization
                    ),
                    offersSystemSettings: offersSystemSettings
                )
                return
            }

            await permissionStore.setEnabled(true, for: permission.kind)
            permission.isEnabled = true
        } catch {
            await permissionStore.setEnabled(false, for: permission.kind)
            permission.isEnabled = false
            alert = IOSPermissionSettingsAlert(
                title: "无法启用\(permission.kind.title)权限",
                message: error.localizedDescription
            )
        }
    }

    private func rejectEnable(
        _ permission: IOSPermissionToggleState,
        message: String,
        offersSystemSettings: Bool = false
    ) async {
        await permissionStore.setEnabled(false, for: permission.kind)
        permission.isEnabled = false
        alert = IOSPermissionSettingsAlert(
            title: "无法启用\(permission.kind.title)权限",
            message: message,
            offersSystemSettings: offersSystemSettings
        )
    }

    private func effectiveToggleValue(
        storedValue: Bool,
        authorization: IOSPermissionAuthorization
    ) -> Bool {
        if authorization == .unknown {
            return storedValue
        }
        return storedValue && authorization.allowsAgentAccess
    }

    private func denialMessage(
        for permission: IOSPermissionKind,
        authorization: IOSPermissionAuthorization
    ) -> String {
        switch authorization {
        case .denied, .writeOnly:
            "系统未允许 Via Vera 完整访问\(permission.title)，可前往系统设置修改。"
        case .restricted:
            "此设备限制了\(permission.title)权限，当前无法启用。"
        case .unavailable:
            "此设备当前无法使用\(permission.title)权限。"
        case .notDetermined, .unknown:
            "系统没有完成\(permission.title)授权，请稍后重试。"
        case .authorized, .limited, .requested:
            ""
        }
    }
}
