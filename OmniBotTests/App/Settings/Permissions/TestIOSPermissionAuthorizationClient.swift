@testable import Via_Vera

@MainActor
final class TestIOSPermissionAuthorizationClient: IOSPermissionAuthorizationClient {
    var statuses: [IOSPermissionKind: IOSPermissionAuthorization]
    var statusAfterRequest: IOSPermissionAuthorization?
    var requestError: (any Error)?
    private(set) var requestedPermissions: [IOSPermissionKind] = []

    init(statuses: [IOSPermissionKind: IOSPermissionAuthorization]) {
        self.statuses = statuses
    }

    func authorizationStatuses() async -> [IOSPermissionKind: IOSPermissionAuthorization] {
        statuses
    }

    func requestAuthorization(for permission: IOSPermissionKind) async throws {
        requestedPermissions.append(permission)
        if let requestError {
            throw requestError
        }
        if let statusAfterRequest {
            statuses[permission] = statusAfterRequest
        }
    }
}
