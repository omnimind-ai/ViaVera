import Foundation
import Testing
@testable import Via_Vera

@Suite("Preferred chat model")
@MainActor
struct PreferredModelStoreTests {
    @Test("Without a saved choice, the first enabled visible model is selected")
    func initialSelection() throws {
        let suiteName = "PreferredModelStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferredModelStore(defaults: defaults)
        let profiles = try [
            profile("disabled", models: [ModelOption(id: "model")], isEnabled: false),
            profile("empty", models: []),
            profile("hidden", models: [ModelOption(id: "model", isHidden: true)]),
            profile("available", models: [
                ModelOption(id: "hidden", isHidden: true), ModelOption(id: "visible")
            ])
        ]

        #expect(store.selection(in: profiles) == ProviderModelSelection(
            providerID: "available", modelID: "visible"
        ))
        #expect(store.selection(in: Array(profiles.prefix(3))) == nil)
        #expect(store.selection(in: []) == nil)
    }

    @Test("The last manual provider and model survive reload and list reordering")
    func remembersLatestChoice() throws {
        let suiteName = "PreferredModelStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferredModelStore(defaults: defaults)
        let profiles = try [
            profile("first", models: [ModelOption(id: "shared")]),
            profile("second", models: [ModelOption(id: "other"), ModelOption(id: "shared")])
        ]
        let firstChoice = ProviderModelSelection(providerID: "second", modelID: "shared")
        store.remember(firstChoice)

        let reloadedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let reloaded = PreferredModelStore(defaults: reloadedDefaults)
        #expect(reloaded.selection(in: profiles) == firstChoice)
        #expect(reloaded.selection(in: profiles.reversed()) == firstChoice)

        let nextChoice = ProviderModelSelection(providerID: "second", modelID: "other")
        reloaded.remember(nextChoice)
        #expect(store.selection(in: profiles) == nextChoice)
    }

    @Test("Unavailable choices fall back without overwriting the saved preference")
    func fallbackPreservesManualChoice() throws {
        let suiteName = "PreferredModelStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferredModelStore(defaults: defaults)
        let fallback = try profile("first", models: [ModelOption(id: "shared")])
        let preferred = try profile("second", models: [ModelOption(id: "shared")])
        let choice = ProviderModelSelection(providerID: "second", modelID: "shared")
        store.remember(choice)

        var disabled = preferred
        disabled.isEnabled = false
        var hidden = preferred
        hidden.models[0].isHidden = true
        var removed = preferred
        removed.models = []

        for profiles in [[fallback], [fallback, disabled], [fallback, hidden], [fallback, removed]] {
            #expect(store.selection(in: profiles) == ProviderModelSelection(
                providerID: "first", modelID: "shared"
            ))
            #expect(store.selection(in: [fallback, preferred]) == choice)
        }
        #expect(store.selection(in: []) == nil)
        #expect(PreferredModelStore(defaults: defaults).selection(in: [preferred]) == choice)
    }

    private func profile(
        _ id: String,
        models: [ModelOption],
        isEnabled: Bool = true
    ) throws -> ProviderProfile {
        ProviderProfile(
            id: id,
            name: id,
            baseURL: try #require(URL(string: "https://example.com/v1")),
            models: models,
            isEnabled: isEnabled
        )
    }
}
