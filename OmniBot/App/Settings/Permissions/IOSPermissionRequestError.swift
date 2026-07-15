import Foundation

nonisolated enum IOSPermissionRequestError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "此设备无法使用 HealthKit。"
        }
    }
}
