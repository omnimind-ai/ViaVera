import Foundation

enum ToolCallStatus: Hashable {
    case pending
    case running
    case succeeded
    case failed
    case interrupted

    var label: String {
        switch self {
        case .pending:
            String(localized: "等待中")
        case .running:
            String(localized: "执行中")
        case .succeeded:
            String(localized: "成功")
        case .failed:
            String(localized: "失败")
        case .interrupted:
            String(localized: "已中断")
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            "clock"
        case .running:
            "progress.indicator"
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .interrupted:
            "stop.circle.fill"
        }
    }
}
