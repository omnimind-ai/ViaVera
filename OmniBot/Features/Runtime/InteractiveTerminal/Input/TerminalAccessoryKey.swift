import Foundation

nonisolated enum TerminalAccessoryKey: Hashable, Identifiable, Sendable {
    case key(TerminalKey)
    case control
    case alternate

    static let layout: [TerminalAccessoryKey] = [
        .key(.escape),
        .key(.slash),
        .key(.dash),
        .key(.home),
        .key(.arrowUp),
        .key(.end),
        .key(.pageUp),
        .key(.tab),
        .control,
        .alternate,
        .key(.arrowLeft),
        .key(.arrowDown),
        .key(.arrowRight),
        .key(.pageDown)
    ]

    var id: String {
        switch self {
        case .key(let key):
            key.id
        case .control:
            "control"
        case .alternate:
            "alternate"
        }
    }

    var title: String {
        switch self {
        case .key(.escape):
            "ESC"
        case .key(.tab):
            "TAB"
        case .key(.slash):
            "/"
        case .key(.dash):
            "−"
        case .key(.home):
            "HOME"
        case .key(.arrowUp):
            "↑"
        case .key(.end):
            "END"
        case .key(.pageUp):
            "PGUP"
        case .key(.arrowLeft):
            "←"
        case .key(.arrowDown):
            "↓"
        case .key(.arrowRight):
            "→"
        case .key(.pageDown):
            "PGDN"
        case .key(.enter):
            "ENTER"
        case .key(.backspace):
            "⌫"
        case .control:
            "CTRL"
        case .alternate:
            "ALT"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .key(.escape):
            "Escape"
        case .key(.tab):
            "Tab"
        case .key(.slash):
            "斜杠"
        case .key(.dash):
            "短横线"
        case .key(.home):
            "Home"
        case .key(.arrowUp):
            "上方向键"
        case .key(.end):
            "End"
        case .key(.pageUp):
            "Page Up"
        case .key(.arrowLeft):
            "左方向键"
        case .key(.arrowDown):
            "下方向键"
        case .key(.arrowRight):
            "右方向键"
        case .key(.pageDown):
            "Page Down"
        case .key(.enter):
            "回车"
        case .key(.backspace):
            "退格"
        case .control:
            "Control 锁定键"
        case .alternate:
            "Alternate 锁定键"
        }
    }
}
