import Foundation

nonisolated struct NativeToolComponent: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case text, heading, stack, row, section, divider
        case textField, numberField, toggle, picker, button
        case list, value, progress, countdown, totp
    }

    let id: String
    let type: Kind
    var title: String? = nil
    var value: AgentValue? = nil
    var binding: String? = nil
    var action: String? = nil
    var children: [NativeToolComponent]? = nil
    var options: [String]? = nil
    var visibleWhen: AgentValue? = nil
}
