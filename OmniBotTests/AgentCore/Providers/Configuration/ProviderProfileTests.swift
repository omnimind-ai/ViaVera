import Foundation
import Testing
@testable import Via_Vera

struct ProviderProfileTests {
    @Test func profileAndModelRoundTrip() throws {
        let profile = ProviderProfile(
            id: "openai",
            name: "OpenAI",
            baseURL: try #require(URL(string: "https://api.openai.com/v1")),
            wireAPI: .chatCompletions,
            defaultHeaders: ["OpenAI-Organization": "org-example"],
            models: [
                ModelOption(
                    id: "gpt-4.1",
                    displayName: "GPT-4.1",
                    contextWindow: 1_000_000,
                    maxOutputTokens: 32_768,
                    supportsTools: true,
                    supportsReasoning: true
                )
            ]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ProviderProfile.self, from: data)

        #expect(decoded == profile)
        #expect(decoded.apiKeyAccount == "provider.openai")
        #expect(!String(decoding: data, as: UTF8.self).contains("apiKey"))
    }

    @Test func wireAPIRawValuesAreStable() throws {
        let data = try JSONEncoder().encode(WireAPI.chatCompletions)
        #expect(String(decoding: data, as: UTF8.self) == "\"chat_completions\"")
        #expect(try JSONDecoder().decode(WireAPI.self, from: data) == .chatCompletions)
    }

    @Test func legacyModelMetadataDecodesAsUserConfiguration() throws {
        let data = Data(
            #"""
            {
              "id": "legacy-model",
              "displayName": "Legacy Model",
              "contextWindow": 128000,
              "maxOutputTokens": 8192,
              "supportsTools": true,
              "supportsReasoning": false,
              "modalities": ["text"]
            }
            """#.utf8
        )

        let model = try JSONDecoder().decode(ModelOption.self, from: data)

        #expect(model.id == "legacy-model")
        #expect(!model.isHidden)
        #expect(model.modelsDevProviderID == nil)
        #expect(model.isMetadataOverridden)
    }
}
