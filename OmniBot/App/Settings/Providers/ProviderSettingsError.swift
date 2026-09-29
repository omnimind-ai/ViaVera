import Foundation

enum ProviderSettingsError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingModel
    case modelNotFound(String)
    case missingProvider
    case missingAPIKey
    case apiKeyRequiresReentry
    case endpointChangeRequiresNewAPIKey
    case secureSaveFailed(String)
    case secureDeleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            String(localized: "请输入有效的 HTTPS API Base URL；仅本机回环地址可使用 HTTP。")
        case .missingModel:
            String(localized: "请输入 Agent 使用的模型 ID。")
        case let .modelNotFound(identifier):
            String(localized: "当前服务商中不存在模型“\(identifier)”。")
        case .missingProvider:
            String(localized: "请先在输入框中选择模型。")
        case .missingAPIKey:
            String(localized: "请为当前服务商填写 API Key。")
        case .apiKeyRequiresReentry:
            String(localized: "已存储的 API Key 未绑定到当前 API 端点，请重新输入后保存。")
        case .endpointChangeRequiresNewAPIKey:
            String(localized: "更改 API 端点时必须重新输入 API Key，旧端点的密钥不会自动复用。")
        case let .secureSaveFailed(message):
            String(localized: "无法安全保存模型服务配置：\(message)")
        case let .secureDeleteFailed(message):
            String(localized: "无法完整删除模型服务凭据：\(message)")
        }
    }
}
