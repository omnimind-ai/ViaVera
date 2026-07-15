import SwiftUI

struct ModelVendorIcon: View {
    let model: ModelOption?
    let provider: ProviderProfile?
    let size: Double
    let forceMonochrome: Bool

    init(
        model: ModelOption?,
        provider: ProviderProfile?,
        size: Double = 16,
        forceMonochrome: Bool = false
    ) {
        self.model = model
        self.provider = provider
        self.size = size
        self.forceMonochrome = forceMonochrome
    }

    var body: some View {
        Group {
            if let assetName = ModelVendorCatalog.assetName(for: model, provider: provider) {
                Image(assetName)
                    .renderingMode(shouldRenderAsTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: ModelVendorCatalog.symbolName(for: model, provider: provider))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var shouldRenderAsTemplate: Bool {
        forceMonochrome
            || ModelVendorCatalog.usesTemplateRendering(for: model, provider: provider)
    }
}
