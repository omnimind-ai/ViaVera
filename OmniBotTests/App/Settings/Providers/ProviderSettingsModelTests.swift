import Foundation
import Testing
@testable import Via_Vera

@Suite("Provider settings")
@MainActor
struct ProviderSettingsModelTests {
    @Test("Editing a provider preserves transport configuration")
    func editingPreservesTransportConfiguration() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ProviderProfile(
            id: "provider",
            name: "Provider",
            baseURL: try #require(URL(string: "https://example.com/v1")),
            wireAPI: .responses,
            defaultHeaders: ["X-Tenant": "tenant-a"],
            models: [ModelOption(id: "configured-model")],
            isEnabled: false
        )
        try await store.upsert(profile)
        let model = ProviderSettingsModel(
            store: store,
            keychain: boundKeychain(for: profile, apiKey: "secret")
        )

        await model.load()
        model.editor.name = "Renamed"
        await model.save()

        let saved = try #require(await store.profile(id: profile.id))
        #expect(saved.wireAPI == .responses)
        #expect(saved.defaultHeaders == ["X-Tenant": "tenant-a"])
        #expect(!saved.isEnabled)
    }

    @Test("The editor displays the Keychain value and clearing it removes the credential")
    func displaysAndClearsAPIKey() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)

        let keychain = boundKeychain(for: profile, apiKey: "existing-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()

        #expect(model.hasStoredAPIKey)
        #expect(model.editor.apiKey == "existing-secret")
        model.editor.name = "Renamed"
        await model.save()
        #expect(try keychain.apiKey(for: profile.id) == "existing-secret")
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: profile))
        #expect(model.hasStoredAPIKey)

        model.editor.apiKey = ""
        await model.save()
        #expect(try keychain.apiKey(for: profile.id) == nil)
        #expect(try keychain.endpointBinding(for: profile.id) == nil)
        #expect(!model.hasStoredAPIKey)
    }

    @Test("Keychain read errors are surfaced and do not populate the editor")
    func keychainReadErrorIsVisible() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)

        let keychain = TestAPIKeyStore(values: [:], readError: .readFailed)
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()

        #expect(model.errorMessage?.contains("test Keychain read failed") == true)
        #expect(model.editor.apiKey.isEmpty)
        #expect(!model.hasStoredAPIKey)
    }

    @Test("An explicitly requested missing model never falls back silently")
    func missingModelDoesNotFallback() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)

        await #expect(throws: ProviderSettingsError.modelNotFound("missing-model")) {
            try await model.runtimeConfiguration(
                providerID: profile.id,
                modelID: "missing-model"
            )
        }
    }

    @Test("A normally bound credential is returned to the runtime")
    func boundCredentialReturnsRuntimeConfiguration() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "bound-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)

        let configuration = try await model.runtimeConfiguration(providerID: profile.id)

        #expect(configuration.profile == profile)
        #expect(configuration.model.id == "configured-model")
        #expect(configuration.apiKey == "bound-secret")
    }

    @Test("Runtime configuration requires the provider chosen in the composer")
    func runtimeConfigurationRequiresProviderID() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let model = ProviderSettingsModel(
            store: store,
            keychain: boundKeychain(for: profile, apiKey: "bound-secret")
        )

        await #expect(throws: ProviderSettingsError.missingProvider) {
            try await model.runtimeConfiguration(modelID: profile.models[0].id)
        }
    }

    @Test("A legacy bare API key is rejected until the user re-enters it")
    func legacyBareAPIKeyIsRejected() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = TestAPIKeyStore(values: [profile.id: "legacy-secret"])
        let model = ProviderSettingsModel(store: store, keychain: keychain)

        await model.load()

        #expect(!model.hasStoredAPIKey)
        await #expect(throws: ProviderSettingsError.apiKeyRequiresReentry) {
            try await model.runtimeConfiguration(providerID: profile.id)
        }
    }

    @Test("A same-ID endpoint injected into providers.json cannot receive the bound key")
    func tamperedEndpointWithSameIDIsRejectedAtRuntime() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "protected-secret")
        let fileURL = directory.appendingPathComponent("providers.json")

        let persistedData = try Data(contentsOf: fileURL)
        var persistedObject = try #require(
            JSONSerialization.jsonObject(with: persistedData) as? [String: Any]
        )
        var profiles = try #require(persistedObject["profiles"] as? [[String: Any]])
        profiles[0]["baseURL"] = "https://attacker.example/v1"
        persistedObject["profiles"] = profiles
        let tamperedData = try JSONSerialization.data(
            withJSONObject: persistedObject,
            options: [.sortedKeys]
        )
        try tamperedData.write(to: fileURL, options: [.atomic])
        try await store.reload()

        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await #expect(throws: ProviderSettingsError.apiKeyRequiresReentry) {
            try await model.runtimeConfiguration(providerID: profile.id)
        }
        #expect(try keychain.apiKey(for: profile.id) == "protected-secret")
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: profile))
    }

    @Test("A same-ID routing header change cannot receive the bound key")
    func tamperedDefaultHeaderWithSameIDIsRejectedAtRuntime() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ProviderProfile(
            id: "provider",
            name: "Provider",
            baseURL: try #require(URL(string: "https://gateway.example/v1")),
            defaultHeaders: ["X-Tenant": "tenant-a"],
            models: [ModelOption(id: "configured-model")]
        )
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "protected-secret")
        let fileURL = directory.appendingPathComponent("providers.json")

        let persistedData = try Data(contentsOf: fileURL)
        var persistedObject = try #require(
            JSONSerialization.jsonObject(with: persistedData) as? [String: Any]
        )
        var profiles = try #require(persistedObject["profiles"] as? [[String: Any]])
        var headers = try #require(profiles[0]["defaultHeaders"] as? [String: Any])
        headers["X-Tenant"] = "tenant-b"
        profiles[0]["defaultHeaders"] = headers
        persistedObject["profiles"] = profiles
        try JSONSerialization.data(withJSONObject: persistedObject, options: [.sortedKeys])
            .write(to: fileURL, options: [.atomic])
        try await store.reload()

        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await #expect(throws: ProviderSettingsError.apiKeyRequiresReentry) {
            try await model.runtimeConfiguration(providerID: profile.id)
        }
        #expect(try keychain.apiKey(for: profile.id) == "protected-secret")
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: profile))
    }

    @Test("Changing an endpoint rebinds the API key displayed in the editor")
    func endpointChangeRebindsDisplayedAPIKey() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()

        model.editor.baseURL = "https://new.example/v1"
        await model.save()

        #expect(model.errorMessage == nil)
        #expect(await store.profile(id: profile.id)?.baseURL.absoluteString == "https://new.example/v1")
        #expect(try keychain.apiKey(for: profile.id) == "old-secret")
        let savedProfile = try #require(await store.profile(id: profile.id))
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: savedProfile))
        #expect(keychain.stagingValues().isEmpty)
    }

    @Test("Endpoint and credential commit in security order")
    func endpointAndCredentialCommitSecurely() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        keychain.clearEvents()

        model.editor.baseURL = "https://new.example/v1"
        model.editor.apiKey = "new-secret"
        await model.save()

        #expect(model.errorMessage == nil)
        #expect(await store.profile(id: profile.id)?.baseURL.absoluteString == "https://new.example/v1")
        #expect(try keychain.apiKey(for: profile.id) == "new-secret")
        let savedProfile = try #require(await store.profile(id: profile.id))
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: savedProfile))
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)

        let events = keychain.events()
        let stagingSave = try #require(events.firstIndex(where: {
            if case let .save(id) = $0 { return id.contains(".staging.") }
            return false
        }))
        let canonicalDelete = try #require(events.firstIndex(of: .delete(profile.id)))
        let canonicalBindingDelete = try #require(events.firstIndex(of: .deleteBinding(profile.id)))
        let canonicalSave = try #require(events.firstIndex(of: .save(profile.id)))
        let canonicalBindingSave = try #require(events.firstIndex(of: .saveBinding(profile.id)))
        #expect(stagingSave < canonicalDelete)
        #expect(canonicalDelete < canonicalSave)
        #expect(canonicalBindingDelete < canonicalSave)
        #expect(canonicalSave < canonicalBindingSave)
    }

    @Test("Staging Keychain failure leaves the old endpoint and key untouched")
    func stagingFailureLeavesSnapshotUntouched() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        keychain.failStagingSave = true
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()

        model.editor.baseURL = "https://new.example/v1"
        model.editor.apiKey = "new-secret"
        await model.save()

        #expect(model.errorMessage?.contains("临时 API Key 写入失败") == true)
        #expect(await store.profile(id: profile.id)?.baseURL == profile.baseURL)
        #expect(try keychain.apiKey(for: profile.id) == "old-secret")
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: profile))
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)
    }

    @Test("Canonical deletion failure prevents endpoint persistence and leaves no usable partial pair")
    func canonicalDeleteFailureLeavesRetryableSafeState() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        keychain.canonicalKeyDeleteFailuresRemaining = 1

        model.editor.baseURL = "https://new.example/v1"
        model.editor.apiKey = "new-secret"
        await model.save()

        #expect(model.errorMessage?.contains("清理旧凭据") == true)
        #expect(await store.profile(id: profile.id)?.baseURL == profile.baseURL)
        #expect(try keychain.apiKey(for: profile.id) == "old-secret")
        #expect(try keychain.endpointBinding(for: profile.id) == nil)
        #expect(!model.hasStoredAPIKey)
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)
    }

    @Test("Endpoint persistence failure restores the old canonical key")
    func persistenceFailureRestoresCredentialSnapshot() async throws {
        let (store, directory) = try makeStore()
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()

        try FileManager.default.removeItem(at: directory)
        _ = FileManager.default.createFile(atPath: directory.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: directory) }

        model.editor.baseURL = "https://new.example/v1"
        model.editor.apiKey = "new-secret"
        await model.save()

        #expect(model.errorMessage?.contains("新端点写入失败") == true)
        #expect(await store.profile(id: profile.id)?.baseURL == profile.baseURL)
        #expect(try keychain.apiKey(for: profile.id) == "old-secret")
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: profile))
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)
    }

    @Test("Canonical promotion failure keeps the new endpoint credential-free")
    func promotionFailureNeverPairsOldKeyWithNewEndpoint() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        keychain.failCanonicalSave = true

        model.editor.baseURL = "https://new.example/v1"
        model.editor.apiKey = "new-secret"
        await model.save()

        #expect(model.errorMessage?.contains("新凭据写入失败") == true)
        #expect(await store.profile(id: profile.id)?.baseURL.absoluteString == "https://new.example/v1")
        #expect(try keychain.apiKey(for: profile.id) == nil)
        #expect(try keychain.endpointBinding(for: profile.id) == nil)
        #expect(!model.hasStoredAPIKey)
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)
    }

    @Test("Endpoint-binding promotion failure removes the newly promoted key")
    func bindingPromotionFailureLeavesNewEndpointCredentialFree() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        keychain.failCanonicalBindingSave = true

        model.editor.baseURL = "https://new.example/v1"
        model.editor.apiKey = "new-secret"
        await model.save()

        #expect(model.errorMessage?.contains("新凭据写入失败") == true)
        #expect(await store.profile(id: profile.id)?.baseURL.absoluteString == "https://new.example/v1")
        #expect(try keychain.apiKey(for: profile.id) == nil)
        #expect(try keychain.endpointBinding(for: profile.id) == nil)
        #expect(!model.hasStoredAPIKey)
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)
    }

    @Test("Profile deletion retains metadata after a credential failure and succeeds on retry")
    func deleteProviderRetriesCredentialCleanupBeforeRemovingMetadata() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = configuredProfile()
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        keychain.canonicalKeyDeleteFailuresRemaining = 1

        await model.delete(profile.id)

        #expect(await store.profile(id: profile.id) == profile)
        #expect(try keychain.apiKey(for: profile.id) == "secret")
        #expect(try keychain.endpointBinding(for: profile.id) == nil)
        #expect(model.errorMessage?.contains("API Key 删除失败") == true)
        #expect(!model.hasStoredAPIKey)

        await model.delete(profile.id)

        #expect(await store.profile(id: profile.id) == nil)
        #expect(try keychain.apiKey(for: profile.id) == nil)
        #expect(try keychain.endpointBinding(for: profile.id) == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("Editing a provider only changes that provider")
    func editingProviderOnlyChangesThatProvider() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let activeProfile = configuredProfile()
        let editedProfile = ProviderProfile(
            id: "edited-provider",
            name: "Edited Provider",
            baseURL: URL(string: "https://edited.example/v1")!,
            models: [ModelOption(id: "edited-model")]
        )
        try await store.upsert(activeProfile)
        try await store.upsert(editedProfile)
        let keychain = TestAPIKeyStore(
            values: [
                activeProfile.id: "active-secret",
                editedProfile.id: "edited-secret"
            ],
            bindings: [
                activeProfile.id: endpointIdentity(for: activeProfile),
                editedProfile.id: endpointIdentity(for: editedProfile)
            ]
        )
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()

        await model.edit(editedProfile.id)

        #expect(model.editor.id == editedProfile.id)
        #expect(model.editor.name == editedProfile.name)
        #expect(model.hasStoredAPIKey)

        model.editor.name = "Renamed Edited Provider"
        await model.save()

        #expect(await store.profile(id: editedProfile.id)?.name == "Renamed Edited Provider")
        #expect(await store.profile(id: activeProfile.id) == activeProfile)

        model.editor.apiKey = ""
        await model.save()

        #expect(try keychain.apiKey(for: editedProfile.id) == nil)
        #expect(try keychain.endpointBinding(for: editedProfile.id) == nil)
        #expect(try keychain.apiKey(for: activeProfile.id) == "active-secret")
        #expect(try keychain.endpointBinding(for: activeProfile.id) == endpointIdentity(for: activeProfile))

        await model.delete(editedProfile.id)

        #expect(await store.profile(id: editedProfile.id) == nil)
        #expect(await store.profile(id: activeProfile.id) == activeProfile)
    }

    @Test("Reordering providers persists the list order")
    func reorderingProvidersPersistsOrder() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = configuredProfile()
        let second = ProviderProfile(
            id: "second-provider",
            name: "Second Provider",
            baseURL: URL(string: "https://second.example/v1")!,
            models: [ModelOption(id: "second-model")]
        )
        let third = ProviderProfile(
            id: "third-provider",
            name: "Third Provider",
            baseURL: URL(string: "https://third.example/v1")!,
            models: [ModelOption(id: "third-model")]
        )
        try await store.upsert(first)
        try await store.upsert(second)
        try await store.upsert(third)
        let model = ProviderSettingsModel(store: store, keychain: TestAPIKeyStore(values: [:]))
        await model.load()

        await model.moveProfiles(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        #expect(model.profiles.map { $0.id } == [second.id, third.id, first.id])
        #expect(await store.profiles().map { $0.id } == [second.id, third.id, first.id])
    }

    @Test("Refreshing models updates catalog metadata and preserves custom overrides")
    func refreshModelsMergesAutomaticAndCustomModels() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let automatic = ModelOption(
            id: "automatic",
            displayName: "Old automatic name",
            modelsDevProviderID: "openai",
            isMetadataOverridden: false
        )
        let custom = ModelOption(id: "custom", displayName: "My Custom Model")
        let profile = ProviderProfile(
            id: "provider",
            name: "Provider",
            baseURL: try #require(URL(string: "https://example.com/v1")),
            models: [automatic, custom]
        )
        try await store.upsert(profile)
        let keychain = boundKeychain(for: profile, apiKey: "secret")
        let discovered = [
            ModelOption(
                id: "automatic",
                displayName: "Fresh automatic name",
                contextWindow: 400_000,
                modelsDevProviderID: "openai",
                isMetadataOverridden: false
            ),
            ModelOption(
                id: "new-model",
                displayName: "New Model",
                modelsDevProviderID: "openai",
                isMetadataOverridden: false
            )
        ]
        let model = ProviderSettingsModel(
            store: store,
            keychain: keychain,
            modelDiscovery: TestModelDiscovery(
                result: ModelDiscoveryResult(models: discovered, notice: nil)
            )
        )
        await model.load()

        await model.refreshModels(model.editor)

        let savedModels = try #require(await store.profile(id: profile.id)?.models)
        #expect(savedModels.map { $0.id } == ["automatic", "new-model", "custom"])
        #expect(savedModels[0].displayName == "Fresh automatic name")
        #expect(savedModels[0].contextWindow == 400_000)
        #expect(savedModels[2].displayName == "My Custom Model")
        #expect(savedModels[2].isMetadataOverridden)
        #expect(model.modelRefreshNotice == nil)
    }

    @Test("Concurrent saves serialize endpoint and credential transactions")
    func concurrentSavesAreSerialized() async throws {
        let profile = configuredProfile()
        let store = ControlledProviderStore(profile: profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        await store.delayNextUpsert()

        model.editor.baseURL = "https://first.example/v1"
        model.editor.apiKey = "first-secret"
        let firstSave = Task { @MainActor in
            await model.save()
        }
        await store.waitUntilUpsertIsDelayed()

        // While the first save is suspended after disconnecting the old key,
        // enqueue a second editor snapshot. It must not enter Keychain before
        // the first endpoint/key transaction is complete.
        model.editor.baseURL = "https://second.example/v1"
        model.editor.apiKey = "second-secret"
        let secondStarted = TestFlag()
        let secondSave = Task { @MainActor in
            secondStarted.set()
            await model.save()
        }
        while !secondStarted.value() {
            await Task.yield()
        }

        #expect(keychain.stagingValues().values.sorted() == ["first-secret"])
        #expect(try keychain.apiKey(for: profile.id) == nil)

        await store.resumeDelayedUpsert()
        await firstSave.value
        await secondSave.value

        #expect(await store.profile(id: profile.id)?.baseURL.absoluteString == "https://second.example/v1")
        #expect(try keychain.apiKey(for: profile.id) == "second-secret")
        let finalProfile = try #require(await store.profile(id: profile.id))
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: finalProfile))
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)
        #expect(model.editor.apiKey == "second-secret")
        #expect(model.errorMessage == nil)
    }

    @Test("Clearing an API key waits for an in-flight save transaction")
    func clearingAPIKeySerializesWithSave() async throws {
        let profile = configuredProfile()
        let store = ControlledProviderStore(profile: profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        await store.delayNextUpsert()

        model.editor.name = "Updated Provider"
        model.editor.apiKey = "new-secret"
        let save = Task { @MainActor in
            await model.save()
        }
        await store.waitUntilUpsertIsDelayed()

        model.editor.apiKey = ""
        let clearingStarted = TestFlag()
        let clearing = Task { @MainActor in
            clearingStarted.set()
            await model.save()
        }
        while !clearingStarted.value() {
            await Task.yield()
        }

        // The synchronous Keychain deletion is inside the same model gate, so
        // it cannot run while the async save is suspended in provider storage.
        #expect(try keychain.apiKey(for: profile.id) == "old-secret")

        await store.resumeDelayedUpsert()
        await save.value
        await clearing.value

        #expect(await store.profile(id: profile.id)?.name == "Updated Provider")
        #expect(try keychain.apiKey(for: profile.id) == nil)
        #expect(try keychain.endpointBinding(for: profile.id) == nil)
        #expect(!model.hasStoredAPIKey)
        #expect(keychain.stagingValues().isEmpty)
        #expect(keychain.stagingBindings().isEmpty)
    }

    @Test("Runtime configuration waits for an in-flight endpoint transaction")
    func runtimeConfigurationSerializesWithSave() async throws {
        let profile = configuredProfile()
        let store = ControlledProviderStore(profile: profile)
        let keychain = boundKeychain(for: profile, apiKey: "old-secret")
        let model = ProviderSettingsModel(store: store, keychain: keychain)
        await model.load()
        await store.delayNextUpsert()

        model.editor.baseURL = "https://new.example/v1"
        model.editor.apiKey = "new-secret"
        let save = Task { @MainActor in
            await model.save()
        }
        await store.waitUntilUpsertIsDelayed()

        let readStarted = TestFlag()
        let readCompleted = TestFlag()
        let configurationRead = Task { @MainActor in
            readStarted.set()
            let configuration = try await model.runtimeConfiguration(
                providerID: profile.id,
                modelID: "configured-model"
            )
            readCompleted.set()
            return configuration
        }
        while !readStarted.value() {
            await Task.yield()
        }

        // The save has disconnected the old key but has not committed the new
        // endpoint. A runtime read must wait instead of combining either side.
        #expect(!readCompleted.value())
        #expect(try keychain.apiKey(for: profile.id) == nil)

        await store.resumeDelayedUpsert()
        await save.value
        let configuration = try await configurationRead.value

        #expect(configuration.profile.baseURL.absoluteString == "https://new.example/v1")
        #expect(configuration.apiKey == "new-secret")
        #expect(try keychain.endpointBinding(for: profile.id) == endpointIdentity(for: configuration.profile))
    }

    private func makeStore() throws -> (ProviderStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try ProviderStore(fileURL: directory.appendingPathComponent("providers.json")), directory)
    }

    private func configuredProfile() -> ProviderProfile {
        ProviderProfile(
            id: "provider",
            name: "Provider",
            baseURL: URL(string: "https://example.com/v1")!,
            models: [ModelOption(id: "configured-model")]
        )
    }

    private func endpointIdentity(for profile: ProviderProfile) -> String {
        ProviderEndpointIdentity.canonical(for: profile)
    }

    private func boundKeychain(
        for profile: ProviderProfile,
        apiKey: String
    ) -> TestAPIKeyStore {
        TestAPIKeyStore(
            values: [profile.id: apiKey],
            bindings: [profile.id: endpointIdentity(for: profile)]
        )
    }
}

nonisolated private enum TestAPIKeyStoreError: Error, LocalizedError {
    case readFailed
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .readFailed:
            "test Keychain read failed"
        case .saveFailed:
            "test Keychain save failed"
        case .deleteFailed:
            "test Keychain delete failed"
        }
    }
}

nonisolated private enum TestAPIKeyEvent: Equatable {
    case save(String)
    case read(String)
    case delete(String)
    case saveBinding(String)
    case readBinding(String)
    case deleteBinding(String)
}

nonisolated private final class TestAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private var values: [String: String]
    private var bindings: [String: String]
    private let readError: TestAPIKeyStoreError?
    private var recordedEvents: [TestAPIKeyEvent] = []
    var failStagingSave = false
    var failStagingBindingSave = false
    var failCanonicalSave = false
    var failCanonicalBindingSave = false
    var canonicalKeyDeleteFailuresRemaining = 0
    var canonicalBindingDeleteFailuresRemaining = 0

    init(
        values: [String: String],
        bindings: [String: String] = [:],
        readError: TestAPIKeyStoreError? = nil
    ) {
        self.values = values
        self.bindings = bindings
        self.readError = readError
    }

    func saveAPIKey(_ apiKey: String, for providerID: String) throws {
        recordedEvents.append(.save(providerID))
        if providerID.hasPrefix("__omnibot.staging."), failStagingSave {
            throw TestAPIKeyStoreError.saveFailed
        }
        if !providerID.hasPrefix("__omnibot.staging."), failCanonicalSave {
            throw TestAPIKeyStoreError.saveFailed
        }
        values[providerID] = apiKey
    }

    func apiKey(for providerID: String) throws -> String? {
        recordedEvents.append(.read(providerID))
        if let readError { throw readError }
        return values[providerID]
    }

    func deleteAPIKey(for providerID: String) throws {
        recordedEvents.append(.delete(providerID))
        if !providerID.hasPrefix("__omnibot.staging."),
           canonicalKeyDeleteFailuresRemaining > 0 {
            canonicalKeyDeleteFailuresRemaining -= 1
            throw TestAPIKeyStoreError.deleteFailed
        }
        values[providerID] = nil
    }

    func saveEndpointBinding(_ endpointIdentity: String, for providerID: String) throws {
        recordedEvents.append(.saveBinding(providerID))
        if providerID.hasPrefix("__omnibot.staging."), failStagingBindingSave {
            throw TestAPIKeyStoreError.saveFailed
        }
        if !providerID.hasPrefix("__omnibot.staging."), failCanonicalBindingSave {
            throw TestAPIKeyStoreError.saveFailed
        }
        bindings[providerID] = endpointIdentity
    }

    func endpointBinding(for providerID: String) throws -> String? {
        recordedEvents.append(.readBinding(providerID))
        if let readError { throw readError }
        return bindings[providerID]
    }

    func deleteEndpointBinding(for providerID: String) throws {
        recordedEvents.append(.deleteBinding(providerID))
        if !providerID.hasPrefix("__omnibot.staging."),
           canonicalBindingDeleteFailuresRemaining > 0 {
            canonicalBindingDeleteFailuresRemaining -= 1
            throw TestAPIKeyStoreError.deleteFailed
        }
        bindings[providerID] = nil
    }

    func events() -> [TestAPIKeyEvent] {
        recordedEvents
    }

    func clearEvents() {
        recordedEvents.removeAll()
    }

    func stagingValues() -> [String: String] {
        values.filter { $0.key.hasPrefix("__omnibot.staging.") }
    }

    func stagingBindings() -> [String: String] {
        bindings.filter { $0.key.hasPrefix("__omnibot.staging.") }
    }
}

nonisolated private final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    func set() {
        lock.lock()
        storedValue = true
        lock.unlock()
    }

    func value() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

private actor ControlledProviderStore: ProviderStoring {
    private var storedProfiles: [ProviderProfile]
    private var shouldDelayNextUpsert = false
    private var upsertIsDelayed = false
    private var delayedUpsertContinuation: CheckedContinuation<Void, Never>?
    private var delayObservers: [CheckedContinuation<Void, Never>] = []

    init(profile: ProviderProfile) {
        storedProfiles = [profile]
    }

    func profiles() -> [ProviderProfile] {
        storedProfiles
    }

    func profile(id: String) -> ProviderProfile? {
        storedProfiles.first { $0.id == id }
    }

    func upsert(_ profile: ProviderProfile) async throws {
        try ProviderStore.validate(profile)
        if shouldDelayNextUpsert {
            shouldDelayNextUpsert = false
            upsertIsDelayed = true
            let observers = delayObservers
            delayObservers.removeAll()
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                delayedUpsertContinuation = continuation
            }
            upsertIsDelayed = false
        }

        if let index = storedProfiles.firstIndex(where: { $0.id == profile.id }) {
            storedProfiles[index] = profile
        } else {
            storedProfiles.append(profile)
        }
    }

    func remove(id: String) throws {
        guard let index = storedProfiles.firstIndex(where: { $0.id == id }) else {
            throw ProviderStoreError.providerNotFound(id)
        }
        storedProfiles.remove(at: index)
    }

    func reorder(providerIDs: [String]) throws {
        guard providerIDs.count == storedProfiles.count,
              Set(providerIDs) == Set(storedProfiles.map(\.id)) else {
            throw ProviderStoreError.invalidProviderOrder
        }
        let profilesByID = Dictionary(uniqueKeysWithValues: storedProfiles.map { ($0.id, $0) })
        storedProfiles = try providerIDs.map { providerID in
            guard let profile = profilesByID[providerID] else {
                throw ProviderStoreError.invalidProviderOrder
            }
            return profile
        }
    }

    func delayNextUpsert() {
        shouldDelayNextUpsert = true
    }

    func waitUntilUpsertIsDelayed() async {
        guard !upsertIsDelayed else { return }
        await withCheckedContinuation { continuation in
            delayObservers.append(continuation)
        }
    }

    func resumeDelayedUpsert() {
        let continuation = delayedUpsertContinuation
        delayedUpsertContinuation = nil
        continuation?.resume()
    }
}
