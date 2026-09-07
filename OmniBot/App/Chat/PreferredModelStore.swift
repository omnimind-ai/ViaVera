import Foundation

@MainActor
final class PreferredModelStore {
    private static let selectionKey = "via-vera.preferred-model"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func remember(_ selection: ProviderModelSelection) {
        defaults.set(
            ["providerID": selection.providerID, "modelID": selection.modelID],
            forKey: Self.selectionKey
        )
    }

    func selection(in profiles: [ProviderProfile]) -> ProviderModelSelection? {
        if let stored = defaults.dictionary(forKey: Self.selectionKey),
           let providerID = stored["providerID"] as? String,
           let modelID = stored["modelID"] as? String {
            let selection = ProviderModelSelection(providerID: providerID, modelID: modelID)
            if selection.availability(in: profiles) == .available {
                return selection
            }
        }

        // Automatic fallback must not replace the user's last explicit choice.
        for profile in profiles where profile.isEnabled {
            if let model = profile.models.first(where: { !$0.isHidden }) {
                return ProviderModelSelection(providerID: profile.id, modelID: model.id)
            }
        }
        return nil
    }
}
