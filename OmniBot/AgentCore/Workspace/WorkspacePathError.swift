import Foundation

nonisolated public enum WorkspacePathError: Error, LocalizedError, Sendable {
    case unavailableApplicationSupport
    case controlDirectoryInsideWorkspace
    case managedPathIsSymbolicLink(String)
    case absolutePathNotAllowed(String)
    case pathEscapesRoot(String)

    public var errorDescription: String? {
        switch self {
        case .unavailableApplicationSupport:
            "The Application Support directory is unavailable."
        case .controlDirectoryInsideWorkspace:
            "The private Agent control directory must be outside the shared workspace."
        case let .managedPathIsSymbolicLink(path):
            "A managed OmniBot directory cannot be a symbolic link: \(path)"
        case let .absolutePathNotAllowed(path):
            "Absolute workspace path is not allowed: \(path)"
        case let .pathEscapesRoot(path):
            "Path escapes the workspace root: \(path)"
        }
    }
}
