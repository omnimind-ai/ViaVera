import Foundation

actor AgentPermissionStore {
    private static let keyPrefix = "via-vera.agent-permission."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled(_ permission: IOSPermissionKind) -> Bool {
        defaults.bool(forKey: key(for: permission))
    }

    func setEnabled(_ enabled: Bool, for permission: IOSPermissionKind) {
        defaults.set(enabled, forKey: key(for: permission))
    }

    func snapshot() -> [IOSPermissionKind: Bool] {
        Dictionary(uniqueKeysWithValues: IOSPermissionKind.allCases.map {
            ($0, isEnabled($0))
        })
    }

    private func key(for permission: IOSPermissionKind) -> String {
        Self.keyPrefix + permission.rawValue
    }
}
