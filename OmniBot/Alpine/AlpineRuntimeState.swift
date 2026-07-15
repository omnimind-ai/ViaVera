import Foundation

enum AlpineRuntimeState: Equatable, Sendable {
    case idle
    case preparing(progress: Double, message: String)
    case ready
    case failed(message: String)
}
