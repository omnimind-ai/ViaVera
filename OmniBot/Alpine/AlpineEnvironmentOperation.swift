import Foundation

enum AlpineEnvironmentOperation: Equatable, Sendable {
    case idle
    case detecting
    case installing
    case applyingMirror
}
