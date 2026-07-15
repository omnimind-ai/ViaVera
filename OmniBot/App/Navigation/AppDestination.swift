import Foundation

enum AppDestination: Hashable {
    case conversation(UUID)
    case providers
    case soul
    case memory
    case skills
    case runtime
}
