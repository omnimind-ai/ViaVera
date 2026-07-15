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
            "请输入有效的 HTTPS API Base URL；仅本机回环地址可使用 HTTP。"
        case .missingModel:
            "请输入 Agent 使用的模型 ID。"
        case let .modelNotFound(identifier):
            "当前服务商中不存在模型“\(identifier)”。"
        case .missingProvider:
            "请先在输入框中选择模型。"
        case .missingAPIKey:
            "请为当前服务商填写 API Key。"
        case .apiKeyRequiresReentry:
            "已存储的 API Key 未绑定到当前 API 端点，请重新输入后保存。"
        case .endpointChangeRequiresNewAPIKey:
            "更改 API 端点时必须重新输入 API Key，旧端点的密钥不会自动复用。"
        case let .secureSaveFailed(message):
            "无法安全保存模型服务配置：\(message)"
        case let .secureDeleteFailed(message):
            "无法完整删除模型服务凭据：\(message)"
        }
    }
}
