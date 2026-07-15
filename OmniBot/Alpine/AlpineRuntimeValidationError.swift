import Foundation

enum AlpineRuntimeValidationError: LocalizedError {
    case rootFileSystemChecksumMismatch

    var errorDescription: String? {
        switch self {
        case .rootFileSystemChecksumMismatch:
            "内置 Alpine rootfs 校验失败，请重新安装应用。"
        }
    }
}
