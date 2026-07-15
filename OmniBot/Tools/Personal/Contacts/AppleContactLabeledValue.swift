import Foundation

nonisolated struct AppleContactLabeledValue: Hashable, Sendable {
    let label: String
    let value: String
}
