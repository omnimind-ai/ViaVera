import Foundation

nonisolated enum NativeToolCameraEvent: Sendable {
    case running
    case hint(String)
    case payload(String)
    case failure(String)
}
