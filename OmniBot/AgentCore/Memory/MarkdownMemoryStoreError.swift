import Foundation

nonisolated public enum MarkdownMemoryStoreError: Error, Equatable, LocalizedError, Sendable {
    case symbolicLinkNotAllowed(file: String)
    case notRegularFile(file: String)
    case notDirectory(path: String)
    case fileTooLarge(file: String, actualBytes: Int, maximumBytes: Int)
    case dailyFileCountExceeded(actual: Int, maximum: Int)
    case dailyTotalBytesExceeded(actualBytes: Int, maximumBytes: Int)
    case invalidUTF8(file: String)
    case fileSystemFailure(operation: String, path: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case let .symbolicLinkNotAllowed(file):
            "Memory file '\(file)' must not be a symbolic link."
        case let .notRegularFile(file):
            "Memory file '\(file)' is not a regular file."
        case let .notDirectory(path):
            "Memory path '\(path)' is not a directory."
        case let .fileTooLarge(file, actualBytes, maximumBytes):
            "Memory file '\(file)' is \(actualBytes) UTF-8 bytes; the limit is \(maximumBytes) bytes."
        case let .dailyFileCountExceeded(actual, maximum):
            "Daily memory contains at least \(actual) files; the limit is \(maximum) files."
        case let .dailyTotalBytesExceeded(actualBytes, maximumBytes):
            "Daily memory uses at least \(actualBytes) bytes; the limit is \(maximumBytes) bytes."
        case let .invalidUTF8(file):
            "Memory file '\(file)' is not valid UTF-8."
        case let .fileSystemFailure(operation, path, code):
            "Unable to \(operation) memory path '\(path)' (POSIX error \(code))."
        }
    }
}
