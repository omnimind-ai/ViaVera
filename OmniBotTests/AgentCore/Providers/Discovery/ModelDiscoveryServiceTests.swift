import Foundation
import Testing

@testable import Via_Vera

struct ModelDiscoveryServiceTests {
    @Test func usesOmniModelsDevMirrorByDefault() {
        #expect(
            ModelDiscoveryService.defaultCatalogURL.absoluteString
                == "https://omni.1775885.xyz/catalog/models-dev/api.json"
        )
    }

    @Test func buildsModelsURLFromCommonOpenAICompatibleBaseURLs() throws {
        let versioned = try #require(URL(string: "https://api.example.com/v1"))
        let root = try #require(URL(string: "https://api.example.com"))
        let completions = try #require(
            URL(string: "https://api.example.com/v1/chat/completions")
        )

        #expect(
            try ModelDiscoveryService.modelsURL(for: versioned).absoluteString
                == "https://api.example.com/v1/models")
        #expect(
            try ModelDiscoveryService.modelsURL(for: root).absoluteString
                == "https://api.example.com/v1/models")
        #expect(
            try ModelDiscoveryService.modelsURL(for: completions).absoluteString
                == "https://api.example.com/v1/models")
    }

    @Test func modelsDevMetadataEnrichesMatchingProviderModel() throws {
        let data = Data(
            #"""
            {
              "openai": {
                "id": "openai",
                "name": "OpenAI",
                "api": "https://${SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/cortex/v1",
                "models": {
                  "gpt-test": {
                    "id": "gpt-test",
                    "name": "GPT Test",
                    "description": "Test model metadata",
                    "reasoning": true,
                    "tool_call": true,
                    "limit": { "context": 400000, "output": 128000 },
                    "modalities": { "input": ["text", "image"], "output": ["text"] }
                  }
                }
              }
            }
            """#.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let catalog = try decoder.decode(ModelsDevCatalog.self, from: data)
        let profile = ProviderProfile(
            id: "provider",
            name: "OpenAI Compatible",
            baseURL: try #require(URL(string: "https://api.openai.com/v1"))
        )

        let model = try #require(
            catalog.modelOption(
                for: ProviderModelDescriptor(id: "gpt-test", ownedBy: "openai"),
                profile: profile
            )
        )

        #expect(model.displayName == "GPT Test")
        #expect(model.providerName == "OpenAI")
        #expect(model.contextWindow == 400_000)
        #expect(model.maxOutputTokens == 128_000)
        #expect(model.supportsReasoning)
        #expect(model.supportsInput("image"))
        #expect(model.modelsDevProviderID == "openai")
        #expect(!model.isMetadataOverridden)
    }
}
