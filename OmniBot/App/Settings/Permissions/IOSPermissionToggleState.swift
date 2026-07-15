import Observation

@MainActor
@Observable
final class IOSPermissionToggleState: Identifiable {
    let kind: IOSPermissionKind
    var authorization: IOSPermissionAuthorization
    var isEnabled: Bool

    var id: IOSPermissionKind { kind }

    init(
        kind: IOSPermissionKind,
        authorization: IOSPermissionAuthorization = .unknown,
        isEnabled: Bool = false
    ) {
        self.kind = kind
        self.authorization = authorization
        self.isEnabled = isEnabled
    }
}
