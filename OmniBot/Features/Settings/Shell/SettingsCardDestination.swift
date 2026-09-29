import Foundation

enum SettingsCardDestination: String, CaseIterable, Hashable, Identifiable {
    case providers
    case usage
    case soul
    case memory
    case skills
    case permissions
    case appearance
    case workspace
    case runtime

    var id: Self { self }

    var title: String {
        switch self {
        case .providers:
            String(localized: "模型服务")
        case .usage:
            String(localized: "模型用量")
        case .soul:
            "Soul"
        case .memory:
            "Memory"
        case .skills:
            "Skills"
        case .permissions:
            String(localized: "权限")
        case .appearance:
            String(localized: "外观")
        case .workspace:
            String(localized: "工作区")
        case .runtime:
            "Alpine Linux"
        }
    }

    var subtitle: String {
        switch self {
        case .providers:
            String(localized: "服务地址、密钥与默认模型")
        case .usage:
            String(localized: "消息活跃度、Token 消耗与模型分布")
        case .soul:
            String(localized: "Agent 的身份与工作边界")
        case .memory:
            String(localized: "长期记忆、每日记忆与检索")
        case .skills:
            String(localized: "导入、启用与管理 Agent 技能")
        case .permissions:
            permissionSubtitle
        case .appearance:
            String(localized: "聊天背景与显示效果")
        case .workspace:
            String(localized: "浏览 Agent 工作区中的文件与文件夹")
        case .runtime:
            String(localized: "环境检测、组件安装与软件源")
        }
    }

    var systemImage: String {
        switch self {
        case .providers:
            "cpu"
        case .usage:
            "chart.bar.xaxis"
        case .soul:
            "sparkles"
        case .memory:
            "brain.head.profile"
        case .skills:
            "puzzlepiece.extension"
        case .permissions:
            "hand.raised"
        case .appearance:
            "paintbrush"
        case .workspace:
            "folder"
        case .runtime:
            "shippingbox"
        }
    }

    private var permissionSubtitle: String {
#if os(macOS)
        String(localized: "管理健康、日历与通讯录授权")
#else
        String(localized: "管理健康、日历、通讯录与闹钟授权")
#endif
    }
}
