import Foundation

nonisolated enum IOSPermissionAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case limited
    case writeOnly
    case requested
    case denied
    case restricted
    case unavailable
    case unknown

    var allowsAgentAccess: Bool {
        switch self {
        case .authorized, .limited, .requested:
            true
        case .notDetermined, .writeOnly, .denied, .restricted, .unavailable, .unknown:
            false
        }
    }
}
