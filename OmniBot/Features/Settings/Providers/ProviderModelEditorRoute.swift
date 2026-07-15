import Foundation

struct ProviderModelEditorRoute: Identifiable {
    let id: String
    let model: ModelOption?

    static func existing(_ model: ModelOption) -> ProviderModelEditorRoute {
        ProviderModelEditorRoute(id: model.id, model: model)
    }

    static func custom() -> ProviderModelEditorRoute {
        ProviderModelEditorRoute(id: UUID().uuidString, model: nil)
    }
}
