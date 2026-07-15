enum ToolCallStatus: Hashable {
    case pending
    case running
    case succeeded
    case failed
    case interrupted

    var label: String {
        switch self {
        case .pending:
            "等待中"
        case .running:
            "执行中"
        case .succeeded:
            "成功"
        case .failed:
            "失败"
        case .interrupted:
            "已中断"
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
