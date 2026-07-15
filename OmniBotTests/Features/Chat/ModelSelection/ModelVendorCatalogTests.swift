import Foundation
import Testing
@testable import Via_Vera

struct ModelVendorCatalogTests {
    @Test func deepSeekModelUsesBrandAssetAheadOfGenericProviderName() throws {
        let model = ModelOption(
            id: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro"
        )
        let provider = ProviderProfile(
            name: "OpenAI Compatible",
            baseURL: try #require(URL(string: "https://example.com/v1")),
            models: [model]
        )

        #expect(
            ModelVendorCatalog.assetName(for: model, provider: provider)
                == "ProviderVendorDeepSeek"
        )
        #expect(!ModelVendorCatalog.usesTemplateRendering(for: model, provider: provider))
    }

    @Test func providerNameCanResolveDeepSeekWhenModelIDIsCustom() throws {
        let model = ModelOption(id: "chat-model", displayName: "Chat Model")
        let provider = ProviderProfile(
            name: "DeepSeek",
            baseURL: try #require(URL(string: "https://example.com/v1")),
            models: [model]
        )

        #expect(
            ModelVendorCatalog.assetName(for: model, provider: provider)
                == "ProviderVendorDeepSeek"
        )
    }

    @Test func monochromeVendorsUseTemplateRendering() {
        let model = ModelOption(id: "gpt-5", displayName: "GPT-5")

        #expect(ModelVendorCatalog.usesTemplateRendering(for: model, provider: nil))
        #expect(
            ModelVendorCatalog.assetName(for: model, provider: nil)
                == "ProviderVendorOpenAI"
        )
    }

    @Test func unknownModelFallsBackToSystemSymbol() {
        let model = ModelOption(id: "custom-model", displayName: "Custom Model")

        #expect(ModelVendorCatalog.assetName(for: model, provider: nil) == nil)
        #expect(ModelVendorCatalog.symbolName(for: model, provider: nil) == "sparkles")
    }
}
