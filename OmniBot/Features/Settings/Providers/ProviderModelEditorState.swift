import Foundation

struct ProviderModelEditorState {
    let originalID: String?
    var modelID: String
    var displayName: String
    var providerName: String
    var description: String
    var contextWindow: Int?
    var maxOutputTokens: Int?
    var supportsTools: Bool
    var supportsReasoning: Bool
    var supportsImage: Bool
    var supportsPDF: Bool
    var supportsAudio: Bool
    var supportsVideo: Bool
    var isHidden: Bool
    var modelsDevProviderID: String?

    init(model: ModelOption?) {
        originalID = model?.id
        modelID = model?.id ?? ""
        displayName = model?.displayName ?? ""
        providerName = model?.providerName ?? ""
        description = model?.description ?? ""
        contextWindow = model?.contextWindow
        maxOutputTokens = model?.maxOutputTokens
        supportsTools = model?.supportsTools ?? true
        supportsReasoning = model?.supportsReasoning ?? false
        supportsImage = model?.supportsInput("image") ?? false
        supportsPDF = model?.supportsInput("pdf") ?? false
        supportsAudio = model?.supportsInput("audio") ?? false
        supportsVideo = model?.supportsInput("video") ?? false
        isHidden = model?.isHidden ?? false
        modelsDevProviderID = model?.modelsDevProviderID
    }

    var modelOption: ModelOption {
        var modalities = ["text"]
        if supportsImage { modalities.append("image") }
        if supportsPDF { modalities.append("pdf") }
        if supportsAudio { modalities.append("audio") }
        if supportsVideo { modalities.append("video") }

        return ModelOption(
            id: modelID,
            displayName: displayName,
            providerName: providerName,
            description: description,
            contextWindow: contextWindow,
            maxOutputTokens: maxOutputTokens,
            supportsTools: supportsTools,
            supportsReasoning: supportsReasoning,
            modalities: modalities,
            isHidden: isHidden,
            modelsDevProviderID: modelsDevProviderID,
            isMetadataOverridden: true
        )
    }
}
