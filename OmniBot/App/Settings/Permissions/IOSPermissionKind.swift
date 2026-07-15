import Foundation

nonisolated enum IOSPermissionKind: String, CaseIterable, Identifiable, Sendable {
    case healthKit = "healthkit"
    case calendars
    case contacts
    case alarms

    var id: Self { self }

    static var availableOnCurrentPlatform: [Self] {
        allCases.filter(\.isAvailableOnCurrentPlatform)
    }

    var isAvailableOnCurrentPlatform: Bool {
#if os(macOS)
        self != .alarms
#else
        true
#endif
    }

    var title: String {
        switch self {
        case .healthKit:
            "健康"
        case .calendars:
            "日历"
        case .contacts:
            "通讯录"
        case .alarms:
            "闹钟"
        }
    }

    var subtitle: String {
        switch self {
        case .healthKit:
            "读取你明确授权的健康与健身数据"
        case .calendars:
            "读取、创建和管理日历事件"
        case .contacts:
            "查找、创建和管理联系人"
        case .alarms:
            "创建和管理系统闹钟"
        }
    }

    var systemImage: String {
        switch self {
        case .healthKit:
            "heart.fill"
        case .calendars:
            "calendar"
        case .contacts:
            "person.crop.circle"
        case .alarms:
            "alarm"
        }
    }

    static func requiredPermission(forAgentToolName name: String) -> Self? {
        if name.hasPrefix("healthkit_") { return .healthKit }
        if name.hasPrefix("calendar_") { return .calendars }
        if name.hasPrefix("contacts_") { return .contacts }
        if name.hasPrefix("alarm_reminder_") { return .alarms }
        return nil
    }

    static func isAgentToolAvailableOnCurrentPlatform(_ name: String) -> Bool {
        requiredPermission(forAgentToolName: name)?.isAvailableOnCurrentPlatform ?? true
    }
}
