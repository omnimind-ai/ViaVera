import Foundation

enum SettingsCardDestination: String, CaseIterable, Hashable, Identifiable {
    case providers
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
            "模型服务"
        case .soul:
            "Soul"
        case .memory:
            "Memory"
        case .skills:
            "Skills"
        case .permissions:
            "权限"
        case .appearance:
            "外观"
        case .workspace:
            "工作区"
        case .runtime:
            "Alpine Linux"
        }
    }

    var subtitle: String {
        switch self {
        case .providers:
            "服务地址、密钥与默认模型"
        case .soul:
            "Agent 的身份与工作边界"
        case .memory:
            "长期记忆、每日记忆与检索"
        case .skills:
            "导入、启用与管理 Agent 技能"
        case .permissions:
            permissionSubtitle
        case .appearance:
            "聊天背景与显示效果"
        case .workspace:
            "浏览 Agent 工作区中的文件与文件夹"
        case .runtime:
            "环境检测、组件安装与软件源"
        }
    }

    var systemImage: String {
        switch self {
        case .providers:
            "cpu"
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
        "管理健康、日历与通讯录授权"
#else
        "管理健康、日历、通讯录与闹钟授权"
#endif
    }
}
