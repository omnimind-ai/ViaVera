import Foundation
import Testing
@testable import Via_Vera

@Suite("Provider model menu selection")
struct ProviderModelSelectionTests {
    @Test("An enabled visible model uses its regular checked picker entry")
    func visibleSelectionIsAvailable() {
        let profile = makeProfile(models: [ModelOption(id: "visible")])
        let selection = ProviderModelSelection(providerID: profile.id, modelID: "visible")

        #expect(selection.availability(in: [profile]) == .available)
        #expect(!selection.availability(in: [profile]).needsCurrentEntry)
    }

    @Test("A disabled current provider keeps a dedicated current entry")
    func disabledProviderNeedsCurrentEntry() {
        let profile = makeProfile(
            id: "disabled",
            models: [ModelOption(id: "shared")],
            isEnabled: false
        )
        let otherProfile = makeProfile(
            id: "enabled",
            models: [ModelOption(id: "shared")]
        )
        let selection = ProviderModelSelection(providerID: profile.id, modelID: "shared")

        #expect(selection.availability(in: [otherProfile, profile]) == .providerDisabled)
        #expect(selection.availability(in: [otherProfile, profile]).needsCurrentEntry)
    }

    @Test("A hidden current model keeps a dedicated current entry")
    func hiddenModelNeedsCurrentEntry() {
        let profile = makeProfile(models: [ModelOption(id: "hidden", isHidden: true)])
        let selection = ProviderModelSelection(providerID: profile.id, modelID: "hidden")

        #expect(selection.availability(in: [profile]) == .modelHidden)
        #expect(selection.availability(in: [profile]).needsCurrentEntry)
    }

    @Test("Missing configuration still preserves a nonempty current pair")
    func missingSelectionNeedsCurrentEntry() {
        let profile = makeProfile(models: [])

        #expect(
            ProviderModelSelection(providerID: "missing", modelID: "model")
                .availability(in: [profile]) == .providerMissing
        )
        #expect(
            ProviderModelSelection(providerID: profile.id, modelID: "missing")
                .availability(in: [profile]) == .modelMissing
        )
        #expect(
            ProviderModelSelection(providerID: "", modelID: "model")
                .availability(in: [profile]).needsCurrentEntry
        )
    }

    @Test("An empty model identifier represents no current selection")
    func emptyModelHasNoCurrentEntry() {
        let selection = ProviderModelSelection(providerID: "provider", modelID: "")

        #expect(selection.availability(in: []) == .none)
        #expect(!selection.availability(in: []).needsCurrentEntry)
    }

    private func makeProfile(
        id: String = "provider",
        models: [ModelOption],
        isEnabled: Bool = true
    ) -> ProviderProfile {
        ProviderProfile(
            id: id,
            name: id,
            baseURL: URL(string: "https://example.com/v1")!,
            models: models,
            isEnabled: isEnabled
        )
    }
}
