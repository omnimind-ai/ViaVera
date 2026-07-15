import Foundation
import Observation

@MainActor
@Observable
final class ProviderSettingsModel {
    private struct CredentialSnapshot {
        let apiKey: String?
        let endpointBinding: String?

        func isBound(to endpointIdentity: String?) -> Bool {
            apiKey != nil
                && endpointIdentity != nil
                && endpointBinding == endpointIdentity
        }
    }

    private(set) var profiles: [ProviderProfile] = []
    private(set) var hasStoredAPIKey = false
    private(set) var isMutating = false
    private(set) var isRefreshingModels = false
    var editor = ProviderEditorState()
    var errorMessage: String?
    var modelRefreshNotice: String?

    private let store: any ProviderStoring
    private let keychain: any APIKeyStoring
    private let modelDiscovery: any ModelDiscovering
    @ObservationIgnored private var mutationLocked = false
    @ObservationIgnored private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var pendingMutationCount = 0

    init(
        store: any ProviderStoring,
        keychain: any APIKeyStoring,
        modelDiscovery: any ModelDiscovering = ModelDiscoveryService()
    ) {
        self.store = store
        self.keychain = keychain
        self.modelDiscovery = modelDiscovery
    }

    func load() async {
        await withMutation {
            await loadUnlocked()
        }
    }

    func edit(_ providerID: String) async {
        await withMutation {
            await editUnlocked(providerID)
        }
    }

    func createProfile() async {
        let state = ProviderEditorState()
        await withMutation {
            await createProfileUnlocked(state)
        }
    }

    func save() async {
        await save(editor)
    }

    func save(_ state: ProviderEditorState) async {
        // Capture at invocation time. A queued save must not accidentally use
        // editor values that a different in-flight save later clears or edits.
        await withMutation {
            await saveUnlocked(state)
        }
    }

    func delete(_ providerID: String) async {
        await withMutation {
            await deleteProviderUnlocked(providerID)
        }
    }

    func moveProfiles(fromOffsets offsets: IndexSet, toOffset destination: Int) async {
        await withMutation {
            await moveProfilesUnlocked(fromOffsets: offsets, toOffset: destination)
        }
    }

    func refreshModels(_ state: ProviderEditorState) async {
        await withMutation {
            await refreshModelsUnlocked(state)
        }
    }

    @discardableResult
    func upsertModel(_ model: ModelOption, replacing originalID: String?) -> Bool {
        let identifier = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            errorMessage = ProviderSettingsError.missingModel.localizedDescription
            return false
        }
        guard !editor.models.contains(where: { candidate in
            candidate.id == identifier && candidate.id != originalID
        }) else {
            errorMessage = ProviderStoreError.duplicateModelIdentifier(identifier).localizedDescription
            return false
        }
        guard model.contextWindow.map({ $0 > 0 }) ?? true,
              model.maxOutputTokens.map({ $0 > 0 }) ?? true else {
            errorMessage = ProviderStoreError.invalidModelLimits(identifier).localizedDescription
            return false
        }
        if let contextWindow = model.contextWindow,
           let maxOutputTokens = model.maxOutputTokens,
           maxOutputTokens > contextWindow {
            errorMessage = ProviderStoreError.invalidModelLimits(identifier).localizedDescription
            return false
        }

        var normalized = ModelOption(
            id: identifier,
            displayName: model.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            providerName: model.providerName?.trimmingCharacters(in: .whitespacesAndNewlines),
            description: model.description?.trimmingCharacters(in: .whitespacesAndNewlines),
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            supportsTools: model.supportsTools,
            supportsReasoning: model.supportsReasoning,
            modalities: Array(Set(model.modalities + ["text"])).sorted(),
            isHidden: model.isHidden,
            modelsDevProviderID: model.modelsDevProviderID,
            isMetadataOverridden: true
        )
        if normalized.displayName.isEmpty {
            normalized.displayName = identifier
        }
        if normalized.providerName?.isEmpty == true {
            normalized.providerName = nil
        }
        if normalized.description?.isEmpty == true {
            normalized.description = nil
        }

        if let originalID,
           let index = editor.models.firstIndex(where: { $0.id == originalID }) {
            editor.models[index] = normalized
        } else {
            editor.models.append(normalized)
        }
        errorMessage = nil
        return true
    }

    func deleteModel(_ modelID: String) {
        editor.models.removeAll { $0.id == modelID }
    }

    func toggleModelVisibility(_ modelID: String) {
        guard let index = editor.models.firstIndex(where: { $0.id == modelID }) else { return }
        editor.models[index].isHidden.toggle()
    }

    func runtimeConfiguration(
        providerID: String? = nil,
        modelID: String? = nil
    ) async throws -> ProviderRuntimeConfiguration {
        try await withMutation {
            try await runtimeConfigurationUnlocked(
                providerID: providerID,
                modelID: modelID
            )
        }
    }

    private func loadUnlocked() async {
        modelRefreshNotice = nil
        profiles = await store.profiles()

        if profiles.isEmpty {
            await createProfileUnlocked(ProviderEditorState())
            return
        }
        do {
            try loadEditor(providerID: profiles.first?.id)
            errorMessage = nil
        } catch {
            hasStoredAPIKey = false
            errorMessage = error.localizedDescription
        }
    }

    private func editUnlocked(_ providerID: String) async {
        modelRefreshNotice = nil
        profiles = await store.profiles()
        do {
            try loadEditor(providerID: providerID)
            errorMessage = nil
        } catch {
            hasStoredAPIKey = false
            errorMessage = error.localizedDescription
        }
    }

    private func createProfileUnlocked(_ state: ProviderEditorState) async {
        editor = state
        hasStoredAPIKey = false
        modelRefreshNotice = nil
        do {
            let profile = try profile(from: state)
            try await store.upsert(profile)
            profiles = await store.profiles()
            try loadEditor(providerID: profile.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveUnlocked(_ state: ProviderEditorState) async {
        let providerID = state.id
        do {
            let profile = try profile(from: state)
            try ProviderStore.validate(profile)

            let previousProfile = await store.profile(id: profile.id)
            let previousCredentials = try credentialSnapshot(for: profile.id)
            let enteredAPIKey = state.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let visibleAPIKey = enteredAPIKey.isEmpty ? nil : enteredAPIKey
            let endpointIdentity = ProviderEndpointIdentity.canonical(for: profile)
            let previousEndpointIdentity = previousProfile.map {
                ProviderEndpointIdentity.canonical(for: $0)
            }
            let endpointChanged = Self.endpointChanged(
                from: previousProfile,
                to: profile,
                orphanedAPIKeyExists: previousCredentials.apiKey != nil
            )

            let newAPIKey: String?
            if let visibleAPIKey,
               endpointChanged
                || visibleAPIKey != previousCredentials.apiKey
                || previousCredentials.endpointBinding != endpointIdentity {
                newAPIKey = visibleAPIKey
            } else {
                newAPIKey = nil
            }
            let shouldDeleteAPIKey = visibleAPIKey == nil && previousCredentials.apiKey != nil

            hasStoredAPIKey = try await persistSecurely(
                profile,
                previousCredentials: previousCredentials,
                previousEndpointIdentity: previousEndpointIdentity,
                endpointIdentity: endpointIdentity,
                newAPIKey: newAPIKey,
                endpointChanged: endpointChanged
            )
            if shouldDeleteAPIKey, !endpointChanged {
                try deleteCredentialPair(for: profile.id)
                hasStoredAPIKey = false
            }
            profiles = await store.profiles()
            errorMessage = nil
        } catch {
            let saveError = error.localizedDescription
            profiles = await store.profiles()
            do {
                if let currentProfile = await store.profile(id: providerID) {
                    hasStoredAPIKey = try credentialSnapshot(for: providerID).isBound(
                        to: ProviderEndpointIdentity.canonical(for: currentProfile)
                    )
                } else {
                    hasStoredAPIKey = false
                }
                errorMessage = saveError
            } catch {
                hasStoredAPIKey = false
                errorMessage = "\(saveError)\n无法确认当前钥匙串状态：\(error.localizedDescription)"
            }
        }
    }

    private func deleteProviderUnlocked(_ providerID: String?) async {
        guard let providerID else { return }
        do {
            // Credentials must be gone before their only retry handle (the
            // profile ID) is removed from non-secret metadata.
            try deleteCredentialPair(for: providerID)
            try await store.remove(id: providerID)
            profiles = await store.profiles()
            if profiles.isEmpty {
                hasStoredAPIKey = false
                await createProfileUnlocked(ProviderEditorState())
            } else {
                let editorProviderID = profiles.contains(where: { $0.id == editor.id })
                    ? editor.id
                    : profiles.first?.id
                try loadEditor(providerID: editorProviderID)
            }
        } catch {
            let deletionError = error.localizedDescription
            profiles = await store.profiles()
            do {
                let editorProviderID = profiles.contains(where: { $0.id == providerID })
                    ? providerID
                    : profiles.first?.id
                try loadEditor(providerID: editorProviderID)
                errorMessage = deletionError
            } catch {
                hasStoredAPIKey = false
                errorMessage = "\(deletionError)\n无法确认当前钥匙串状态：\(error.localizedDescription)"
            }
        }
    }

    private func moveProfilesUnlocked(fromOffsets offsets: IndexSet, toOffset destination: Int) async {
        guard let reorderedProfiles = Self.reorderedProfiles(
            profiles,
            fromOffsets: offsets,
            toOffset: destination
        ) else {
            return
        }

        profiles = reorderedProfiles
        do {
            try await store.reorder(providerIDs: reorderedProfiles.map(\.id))
            profiles = await store.profiles()
            errorMessage = nil
        } catch {
            profiles = await store.profiles()
            errorMessage = error.localizedDescription
        }
    }

    private func refreshModelsUnlocked(_ state: ProviderEditorState) async {
        isRefreshingModels = true
        modelRefreshNotice = nil
        defer { isRefreshingModels = false }

        await saveUnlocked(state)
        guard errorMessage == nil,
              let profile = await store.profile(id: state.id) else {
            return
        }

        do {
            let credentials = try credentialSnapshot(for: profile.id)
            guard let apiKey = credentials.apiKey else {
                throw ModelDiscoveryError.missingAPIKey
            }
            guard credentials.endpointBinding == ProviderEndpointIdentity.canonical(for: profile) else {
                throw ProviderSettingsError.apiKeyRequiresReentry
            }

            let result = try await modelDiscovery.discoverModels(
                for: profile,
                apiKey: apiKey
            )
            var refreshedState = editor.id == state.id ? editor : state
            refreshedState.models = Self.mergedModels(
                existing: refreshedState.models,
                discovered: result.models
            )
            editor = refreshedState
            modelRefreshNotice = result.notice
            await saveUnlocked(refreshedState)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func mergedModels(
        existing: [ModelOption],
        discovered: [ModelOption]
    ) -> [ModelOption] {
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let discoveredIDs = Set(discovered.map(\.id))
        var merged = discovered.map { discoveredModel in
            guard let existingModel = existingByID[discoveredModel.id] else {
                return discoveredModel
            }
            guard !existingModel.isMetadataOverridden else {
                return existingModel
            }
            var refreshedModel = discoveredModel
            refreshedModel.isHidden = existingModel.isHidden
            return refreshedModel
        }
        merged.append(contentsOf: existing.filter {
            $0.isMetadataOverridden && !discoveredIDs.contains($0.id)
        })
        return merged
    }

    private static func reorderedProfiles(
        _ profiles: [ProviderProfile],
        fromOffsets offsets: IndexSet,
        toOffset destination: Int
    ) -> [ProviderProfile]? {
        guard !offsets.isEmpty,
              destination >= 0,
              destination <= profiles.count,
              offsets.allSatisfy({ profiles.indices.contains($0) }) else {
            return nil
        }

        let movingProfiles = offsets.sorted().map { profiles[$0] }
        var remainingProfiles = profiles.enumerated().compactMap { index, profile in
            offsets.contains(index) ? nil : profile
        }
        let removedBeforeDestination = offsets.reduce(into: 0) { count, index in
            if index < destination {
                count += 1
            }
        }
        let insertionIndex = destination - removedBeforeDestination
        guard remainingProfiles.indices.contains(insertionIndex)
                || insertionIndex == remainingProfiles.endIndex else {
            return nil
        }
        remainingProfiles.insert(contentsOf: movingProfiles, at: insertionIndex)
        return remainingProfiles
    }

    /// FIFO gate for every provider mutation. Main-actor isolation alone is
    /// insufficient because each store `await` is a reentrancy point.
    private func withMutation<Result>(
        _ operation: @MainActor () async throws -> Result
    ) async rethrows -> Result {
        pendingMutationCount += 1
        isMutating = true
        await acquireMutation()
        defer {
            releaseMutation()
            pendingMutationCount -= 1
            isMutating = pendingMutationCount > 0
        }
        return try await operation()
    }

    private func acquireMutation() async {
        if !mutationLocked {
            mutationLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutation() {
        guard !mutationWaiters.isEmpty else {
            mutationLocked = false
            return
        }
        let continuation = mutationWaiters.removeFirst()
        continuation.resume()
    }

    private func runtimeConfigurationUnlocked(
        providerID: String?,
        modelID: String?
    ) async throws -> ProviderRuntimeConfiguration {
        guard let providerID,
              let profile = await store.profile(id: providerID) else {
            throw ProviderSettingsError.missingProvider
        }
        let resolvedModelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model: ModelOption?
        if let resolvedModelID, !resolvedModelID.isEmpty {
            guard let configuredModel = profile.models.first(where: { $0.id == resolvedModelID }) else {
                throw ProviderSettingsError.modelNotFound(resolvedModelID)
            }
            model = configuredModel
        } else {
            model = profile.models.first
        }
        guard let model, !model.id.isEmpty else {
            throw ProviderSettingsError.missingModel
        }
        let credentials = try credentialSnapshot(for: profile.id)
        guard let apiKey = credentials.apiKey else {
            throw ProviderSettingsError.missingAPIKey
        }
        guard credentials.endpointBinding == ProviderEndpointIdentity.canonical(for: profile) else {
            throw ProviderSettingsError.apiKeyRequiresReentry
        }
        return ProviderRuntimeConfiguration(profile: profile, model: model, apiKey: apiKey)
    }

    private func loadEditor(providerID: String?) throws {
        guard let providerID else {
            editor = ProviderEditorState()
            hasStoredAPIKey = false
            return
        }
        guard let profile = profiles.first(where: { $0.id == providerID }) else {
            throw ProviderSettingsError.missingProvider
        }
        let credentials = try credentialSnapshot(for: profile.id)
        let endpointIdentity = ProviderEndpointIdentity.canonical(for: profile)
        let hasBoundAPIKey = credentials.isBound(to: endpointIdentity)
        editor = ProviderEditorState(
            id: profile.id,
            name: profile.name,
            baseURL: profile.baseURL.absoluteString,
            apiKey: hasBoundAPIKey ? credentials.apiKey ?? "" : "",
            protocolType: profile.protocolType,
            wireAPI: profile.wireAPI,
            defaultHeaders: profile.defaultHeaders,
            models: profile.models,
            isEnabled: profile.isEnabled
        )
        hasStoredAPIKey = hasBoundAPIKey
    }

    private func profile(from state: ProviderEditorState) throws -> ProviderProfile {
        guard let baseURL = URL(string: state.baseURL), baseURL.host != nil else {
            throw ProviderSettingsError.invalidBaseURL
        }
        return ProviderProfile(
            id: state.id,
            name: state.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL,
            protocolType: state.protocolType,
            wireAPI: state.wireAPI,
            defaultHeaders: state.defaultHeaders,
            models: state.models,
            isEnabled: state.isEnabled
        )
    }

    /// Coordinates endpoint metadata and its canonical Keychain credential so
    /// an endpoint change can never observe the credential from the other side
    /// of the transaction.
    private func persistSecurely(
        _ profile: ProviderProfile,
        previousCredentials: CredentialSnapshot,
        previousEndpointIdentity: String?,
        endpointIdentity: String,
        newAPIKey: String?,
        endpointChanged: Bool
    ) async throws -> Bool {
        let stagingID = try stageCredential(
            newAPIKey,
            endpointIdentity: endpointIdentity,
            providerID: profile.id
        )

        if endpointChanged {
            // This is intentionally synchronous and happens before the actor
            // hop that persists the new endpoint. Both Keychain records are
            // attempted even when the first deletion fails, leaving either a
            // valid old pair or an unusable partial pair that can be retried.
            let deletionErrors = credentialDeletionErrors(for: profile.id)
            if !deletionErrors.isEmpty {
                var details = [
                    "无法在更改端点前清理旧凭据：\(deletionErrors.joined(separator: "；"))"
                ]
                appendStagingCleanupErrors(stagingID, to: &details)
                throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
            }

            do {
                try await store.upsert(profile)
            } catch {
                var details = ["新端点写入失败：\(error.localizedDescription)"]
                // upsert commits actor state only after its atomic file write
                // succeeds, so a thrown error still means the old endpoint is
                // active and can safely receive its previously bound pair.
                details.append(contentsOf: restoreCredentialPair(
                    previousCredentials,
                    expectedEndpointIdentity: previousEndpointIdentity,
                    providerID: profile.id
                ))
                appendStagingCleanupErrors(stagingID, to: &details)
                throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
            }
        } else {
            do {
                try await store.upsert(profile)
            } catch {
                var details = ["服务配置写入失败：\(error.localizedDescription)"]
                appendStagingCleanupErrors(stagingID, to: &details)
                throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
            }
        }

        if let newAPIKey {
            do {
                // The key and protected endpoint identity become canonical in
                // one non-suspending section, so runtime reads cannot observe
                // the pair halfway through promotion.
                try keychain.saveAPIKey(newAPIKey, for: profile.id)
                try keychain.saveEndpointBinding(endpointIdentity, for: profile.id)
            } catch {
                let prefix = endpointChanged
                    ? "新端点已保存，但新凭据写入失败"
                    : "模型服务凭据写入失败"
                var details = ["\(prefix)：\(error.localizedDescription)"]
                details.append(contentsOf: credentialDeletionErrors(for: profile.id).map {
                    "canonical 凭据清理失败：\($0)"
                })
                if !endpointChanged {
                    details.append(contentsOf: restoreCredentialPair(
                        previousCredentials,
                        expectedEndpointIdentity: previousEndpointIdentity,
                        providerID: profile.id
                    ))
                }
                appendStagingCleanupErrors(stagingID, to: &details)
                throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
            }
        }

        let stagingCleanupErrors = cleanupStagingCredential(stagingID)
        if !stagingCleanupErrors.isEmpty {
            throw ProviderSettingsError.secureSaveFailed(
                stagingCleanupErrors.joined(separator: "；")
            )
        }
        return newAPIKey != nil || previousCredentials.isBound(to: endpointIdentity)
    }

    private func credentialSnapshot(for providerID: String) throws -> CredentialSnapshot {
        let storedAPIKey = try keychain.apiKey(for: providerID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CredentialSnapshot(
            apiKey: storedAPIKey?.isEmpty == false ? storedAPIKey : nil,
            endpointBinding: try keychain.endpointBinding(for: providerID)
        )
    }

    private func stageCredential(
        _ apiKey: String?,
        endpointIdentity: String,
        providerID: String
    ) throws -> String? {
        guard let apiKey else { return nil }
        let stagingID = "__omnibot.staging.\(providerID).\(UUID().uuidString)"

        do {
            try keychain.saveAPIKey(apiKey, for: stagingID)
        } catch {
            var details = ["临时 API Key 写入失败：\(error.localizedDescription)"]
            appendStagingCleanupErrors(stagingID, to: &details)
            throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
        }

        do {
            try keychain.saveEndpointBinding(endpointIdentity, for: stagingID)
        } catch {
            var details = ["临时端点绑定写入失败：\(error.localizedDescription)"]
            appendStagingCleanupErrors(stagingID, to: &details)
            throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
        }

        do {
            let stagedAPIKey = try keychain.apiKey(for: stagingID)
            let stagedBinding = try keychain.endpointBinding(for: stagingID)
            guard stagedAPIKey == apiKey, stagedBinding == endpointIdentity else {
                var details = ["临时凭据校验不一致。"]
                appendStagingCleanupErrors(stagingID, to: &details)
                throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
            }
        } catch let error as ProviderSettingsError {
            throw error
        } catch {
            var details = ["临时凭据读取校验失败：\(error.localizedDescription)"]
            appendStagingCleanupErrors(stagingID, to: &details)
            throw ProviderSettingsError.secureSaveFailed(details.joined(separator: "；"))
        }
        return stagingID
    }

    private func deleteCredentialPair(for providerID: String) throws {
        let errors = credentialDeletionErrors(for: providerID)
        guard errors.isEmpty else {
            throw ProviderSettingsError.secureDeleteFailed(errors.joined(separator: "；"))
        }
    }

    /// Always attempts both records so partial Keychain failures are safe and
    /// a later explicit retry can finish the cleanup.
    private func credentialDeletionErrors(for providerID: String) -> [String] {
        var errors: [String] = []
        do {
            try keychain.deleteAPIKey(for: providerID)
        } catch {
            errors.append("API Key 删除失败：\(error.localizedDescription)")
        }
        do {
            try keychain.deleteEndpointBinding(for: providerID)
        } catch {
            errors.append("端点绑定删除失败：\(error.localizedDescription)")
        }
        return errors
    }

    private func restoreCredentialPair(
        _ snapshot: CredentialSnapshot,
        expectedEndpointIdentity: String?,
        providerID: String
    ) -> [String] {
        guard let apiKey = snapshot.apiKey,
              let expectedEndpointIdentity,
              snapshot.endpointBinding == expectedEndpointIdentity else {
            return []
        }

        do {
            try keychain.saveAPIKey(apiKey, for: providerID)
            try keychain.saveEndpointBinding(expectedEndpointIdentity, for: providerID)
            return []
        } catch {
            var details = ["旧凭据快照恢复失败：\(error.localizedDescription)"]
            details.append(contentsOf: credentialDeletionErrors(for: providerID).map {
                "恢复失败后的凭据清理失败：\($0)"
            })
            return details
        }
    }

    private func appendStagingCleanupErrors(_ stagingID: String?, to details: inout [String]) {
        details.append(contentsOf: cleanupStagingCredential(stagingID))
    }

    private func cleanupStagingCredential(_ stagingID: String?) -> [String] {
        guard let stagingID else { return [] }
        return credentialDeletionErrors(for: stagingID).map {
            "临时凭据清理失败：\($0)"
        }
    }

    private static func endpointChanged(
        from previousProfile: ProviderProfile?,
        to profile: ProviderProfile,
        orphanedAPIKeyExists: Bool
    ) -> Bool {
        guard let previousProfile else {
            // A credential without matching metadata has an unknown origin and
            // must never be attached to a newly created endpoint implicitly.
            return orphanedAPIKeyExists
        }
        return ProviderEndpointIdentity.canonical(for: previousProfile)
            != ProviderEndpointIdentity.canonical(for: profile)
    }
}
