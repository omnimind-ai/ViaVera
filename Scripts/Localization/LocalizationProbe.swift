import Foundation

// This command-line probe runs against the app's built resources without launching OmniBot.
let arguments = CommandLine.arguments
let appPath = arguments[1]
let expectedLanguage = arguments[2]
guard let bundle = Bundle(path: appPath) else {
    fatalError("Cannot load the built application bundle")
}
let isChinese = expectedLanguage == "zh-Hans"
precondition(bundle.developmentLocalization == "en", "Unsupported languages must fall back to English")
precondition(bundle.preferredLocalizations.first == expectedLanguage,
             "Unexpected preferred localization: \(bundle.preferredLocalizations)")
precondition(Set(bundle.localizations).isSuperset(of: ["en", "zh-Hans"]))

func localized(_ key: String) -> String {
    bundle.localizedString(forKey: key, value: nil, table: "Localizable")
}

precondition(localized("设置") == (isChinese ? "设置" : "Settings"))
precondition(localized("快捷聊天") == (isChinese ? "快捷聊天" : "Quick Chat"))
precondition(localized("跟随系统") == (isChinese ? "跟随系统" : "System"))
precondition(localized("发送消息给 OmniBot") == (isChinese ? "发送消息给 OmniBot" : "Send a message to OmniBot"))
precondition(SettingsCardDestination.appearance.title == (isChinese ? "外观" : "Appearance"))
precondition(IOSPermissionKind.contacts.title == (isChinese ? "通讯录" : "Contacts"))
precondition(ModelUsageRange.week.title == (isChinese ? "近 7 天" : "Last 7 Days"))
precondition(SidebarConversationGroup.today.title == (isChinese ? "今天" : "Today"))
precondition(ToolCallStatus.running.label == (isChinese ? "执行中" : "Running"))

// Exercise Foundation interpolation, including integers, two arguments, and literal percent signs.
let days = 12
precondition(String(localized: "近 \(days) 天", bundle: bundle) == (isChinese ? "近 12 天" : "Last 12 Days"))
let status = 429
let detail = "rate limit"
precondition(String(localized: "获取模型失败（HTTP \(status)）：\(detail)", bundle: bundle)
             == (isChinese ? "获取模型失败（HTTP 429）：rate limit" : "Failed to fetch models (HTTP 429): rate limit"))
let rate = 75
let tokens = "1K"
precondition(String(localized: "缓存命中率 \(rate)%，命中读取 \(tokens)", bundle: bundle)
             == (isChinese ? "缓存命中率 75%，命中读取 1K" : "Cache hit rate 75%, cached reads 1K"))
let ready = 3
let total = 9
let readiness = String(localized: "已就绪 \(ready)/\(total) 项。缺失组件会被默认选中，可一键安装并自动复检。", bundle: bundle)
precondition(readiness.hasPrefix(isChinese ? "已就绪 3/9 项。" : "3 of 9 components ready."))

let privacy = bundle.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
precondition(privacy == (isChinese
    ? "Via Vera 使用相机扫描工具中的二维码，识别结果仅在本机处理。"
    : "Via Vera uses the camera to scan QR codes in tools. Results are processed only on this device."))
print("PASS: \(Locale.preferredLanguages) → \(expectedLanguage), region \(Locale.current.identifier)")
