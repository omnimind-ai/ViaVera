import Foundation

nonisolated enum ChatPhotoImportError: LocalizedError, Sendable {
    case unavailable(Int)

    var errorDescription: String? {
        switch self {
        case let .unavailable(index):
            "无法读取所选的第 \(index) 张照片，请重新选择。"
        }
    }
}
