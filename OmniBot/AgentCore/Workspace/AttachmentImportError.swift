import Foundation

nonisolated public enum AttachmentImportError: LocalizedError, Sendable {
    case tooManyFiles(Int)
    case notARegularFile(String)
    case fileTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case let .tooManyFiles(count):
            "一次最多导入 16 个附件，当前选择了 \(count) 个。"
        case let .notARegularFile(name):
            "“\(name)”不是可导入的普通文件。"
        case let .fileTooLarge(name):
            "“\(name)”超过 256 MB 的单文件上限。"
        }
    }
}
