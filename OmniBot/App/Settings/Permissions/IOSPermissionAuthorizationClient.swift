import Foundation

@MainActor
protocol IOSPermissionAuthorizationClient: AnyObject {
    func authorizationStatuses() async -> [IOSPermissionKind: IOSPermissionAuthorization]
    func requestAuthorization(for permission: IOSPermissionKind) async throws
}
