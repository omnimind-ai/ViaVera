import Foundation

nonisolated enum AppearanceSettingsStoreError: LocalizedError, Sendable {
    case invalidImage
    case imageTooLarge
    case corruptedSettings(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "请选择有效的图片文件。"
        case .imageTooLarge:
            "背景图片不能超过 64 MB。"
        case let .corruptedSettings(message):
            "外观设置无法读取：\(message)"
        }
    }
}
