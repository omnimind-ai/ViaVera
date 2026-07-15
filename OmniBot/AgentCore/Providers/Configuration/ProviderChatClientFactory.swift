import Foundation

nonisolated enum ProviderChatClientFactory {
    static func make(
        profile: ProviderProfile,
        session: URLSession = .shared
    ) -> any AgentChatCompleting {
        switch profile.protocolType {
        case .anthropic:
            AnthropicMessagesClient(profile: profile, session: session)
        case .deepSeek:
            OpenAICompatibleClient(profile: profile, session: session)
        case .openAICompatible:
            switch profile.wireAPI {
            case .chatCompletions:
                OpenAICompatibleClient(profile: profile, session: session)
            case .responses:
                OpenAIResponsesClient(profile: profile, session: session)
            }
        }
    }
}
