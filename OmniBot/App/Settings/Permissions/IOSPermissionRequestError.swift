import Foundation

nonisolated enum IOSPermissionRequestError: LocalizedError {
    case healthDataUnavailable
    case unsupportedOnCurrentPlatform(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "此设备无法使用 HealthKit。"
        case let .unsupportedOnCurrentPlatform(permission):
            "此平台不支持\(permission)权限。"
        }
    }
}
