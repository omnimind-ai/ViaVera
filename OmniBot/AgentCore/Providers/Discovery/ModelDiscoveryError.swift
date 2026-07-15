import Foundation

nonisolated enum ModelDiscoveryError: Error, Equatable, LocalizedError, Sendable {
    case invalidBaseURL
    case missingAPIKey
    case invalidHTTPResponse
    case httpError(statusCode: Int, message: String)
    case responseTooLarge(maximumBytes: Int)
    case invalidProviderResponse(String)
    case emptyModelList
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "无法根据当前 Base URL 生成模型列表地址。"
        case .missingAPIKey:
            "请先填写 API Key，再自动获取模型。"
        case .invalidHTTPResponse:
            "模型服务返回了无效的 HTTP 响应。"
        case .httpError(let statusCode, let message):
            "获取模型失败（HTTP \(statusCode)）：\(message)"
        case .responseTooLarge(let maximumBytes):
            "模型列表响应超过安全上限（\(maximumBytes) 字节）。"
        case .invalidProviderResponse(let message):
            "无法解析模型列表：\(message)"
        case .emptyModelList:
            "服务商返回的模型列表为空。"
        case .transport(let message):
            "无法连接模型服务：\(message)"
        }
    }
}
