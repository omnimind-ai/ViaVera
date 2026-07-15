import Foundation

struct ProviderEditorState: Equatable {
    var id = UUID().uuidString
    var name = "OpenAI Compatible"
    var baseURL = "https://api.openai.com/v1"
    var apiKey = ""
    var protocolType: ProviderProtocolType = .openAICompatible
    var wireAPI: WireAPI = .chatCompletions
    var defaultHeaders: [String: String] = [:]
    var models: [ModelOption] = []
    var isEnabled = true
}
