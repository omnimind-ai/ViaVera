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

    func syncData() throws -> Data? {
        guard let value = defaults.dictionary(forKey: Self.selectionKey) as? [String: String] else { return nil }
        return try CloudSyncCoding.encode(value)
    }

    func applySyncData(_ data: Data?, expectedDigest: String?) throws -> Bool {
        guard try syncData().map(CloudSyncRevision.hash) == expectedDigest else { return false }
        if let data {
            let value = try JSONDecoder().decode([String: String].self, from: data)
            guard value.keys.sorted() == ["modelID", "providerID"] else { throw CloudSyncError.invalidData }
            defaults.set(value, forKey: Self.selectionKey)
        } else { defaults.removeObject(forKey: Self.selectionKey) }
        return true
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
