import Foundation

/// The provider-specific HTTP contract used above an API's concrete wire shape.
nonisolated public enum ProviderProtocolType: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case deepSeek = "deepseek"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .openAICompatible:
            "OpenAI 兼容"
        case .deepSeek:
            "DeepSeek"
        case .anthropic:
            "Anthropic"
        }
    }

    public var supportedWireAPIs: [WireAPI] {
        switch self {
        case .openAICompatible:
            WireAPI.allCases
        case .deepSeek, .anthropic:
            [.chatCompletions]
        }
    }

    public var interfaceDisplayName: String {
        switch self {
        case .openAICompatible, .deepSeek:
            "Chat Completions"
        case .anthropic:
            "Messages"
        }
    }
}
