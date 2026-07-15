import Foundation

nonisolated enum WorkspaceBrowserItemKind: String, Hashable, Sendable {
    case directory
    case file
    case symbolicLink
    case other
}
