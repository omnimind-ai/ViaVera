import Foundation

nonisolated enum NativeToolSystemResult: Sendable {
    case text(String), data(Data), confirmed(Bool)
}
