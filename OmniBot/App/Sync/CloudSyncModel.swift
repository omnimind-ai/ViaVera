import Foundation
import Observation

@MainActor
@Observable
final class CloudSyncModel {
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "via-vera.icloud-sync")
            if isEnabled && !oldValue {
                accountChangeAuthorized = true
                requestSync()
            }
            if !isEnabled { statusMessage = String(localized: "同步已关闭，本机和云端数据均保留。") }
        }
    }
    private(set) var isSyncing = false
    private(set) var statusMessage = String(localized: "开启后，在使用应用时自动备份和同步。")
    private(set) var errorMessage: String?
    private(set) var lastSyncDate: Date?
    private(set) var backups: [CloudSyncBackup] = []

    @ObservationIgnored var canApplyChanges: () -> Bool = { true }
    @ObservationIgnored var editingSettings: Set<String> = []
    @ObservationIgnored var didImportChanges: () async -> Void = {}
    @ObservationIgnored private let conversations: ConversationRepository
    @ObservationIgnored private let providers: ProviderStore
    @ObservationIgnored private let keychain: any APIKeyStoring
    @ObservationIgnored private let preferences: PreferredModelStore
    @ObservationIgnored private let files: CloudSyncFileStore
    @ObservationIgnored private let transport: any CloudSyncTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var index: CloudSyncIndex?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var accountChangeAuthorized = false
    @ObservationIgnored private var backgroundExpired = false
    @ObservationIgnored private var requiresRefresh = false
    @ObservationIgnored private var initialDefaultDigests: [String: String] = [:]

    init(conversations: ConversationRepository, providers: ProviderStore,
         preferences: PreferredModelStore, paths: WorkspacePaths, keychain: any APIKeyStoring = KeychainAPIKeyStore(),
         cacheKeychain: any APIKeyStoring = KeychainAPIKeyStore(service: "\(Bundle.main.bundleIdentifier ?? "OmniBot").cloud-sync-cache"),
         transport: any CloudSyncTransport = CloudKitSyncTransport(), defaults: UserDefaults = .standard) {
        self.conversations = conversations
        self.providers = providers
        self.keychain = keychain
        self.preferences = preferences
        self.files = CloudSyncFileStore(paths: paths, keychain: cacheKeychain)
        self.transport = transport
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "via-vera.icloud-sync")
        lastSyncDate = defaults.object(forKey: "via-vera.icloud-last-sync") as? Date
    }

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.synchronize()
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
            }
        }
    }

    func requestSync() {
        guard request == nil else { return }
        request = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await self?.synchronize()
            self?.request = nil
        }
    }

    func synchronize() async {
        guard isEnabled, !isSyncing else { return }
        guard canApplyChanges(), editingSettings.isEmpty else {
            statusMessage = CloudSyncError.busy.localizedDescription
            return
        }
        isSyncing = true
        backgroundExpired = false
        errorMessage = nil
        statusMessage = String(localized: "正在同步 iCloud…")
        let lease = BackgroundExecutionController.shared.begin { [weak self] in
            self?.backgroundExpired = true
        }
        defer {
            BackgroundExecutionController.shared.end(lease)
            isSyncing = false
        }
        var acquiredSession = false
        do {
            var state: CloudSyncIndex
            if let index { state = index } else { state = try await files.loadIndex() }
            let account = try await transport.accountID()
            try checkCanContinue()
            if let previous = state.accountID, previous != account {
                guard accountChangeAuthorized else { throw CloudSyncError.accountChanged }
                // Preserve the previous account's journal locally, but never
                // upload its cached remote-only records into another account.
                try await files.archiveIndex(state)
                state = CloudSyncIndex()
            }
            accountChangeAuthorized = false
            state.accountID = account
            try await transport.beginSession()
            acquiredSession = true
            try await captureLocalChanges(into: &state)
            try await persist(state)

            var more = true
            while more {
                let page = try await transport.fetch(since: state.changeToken)
                try checkCanContinue()
                guard try await transport.accountID() == account else { throw CloudSyncError.accountChanged }
                if page.resetUploadState {
                    state.uploaded.removeAll()
                    state.fullFetchKnownIDs = nil
                    state.fullFetchSeenIDs = nil
                } else if page.beginsFullFetch {
                    state.fullFetchKnownIDs = state.uploaded
                    state.fullFetchSeenIDs = []
                }
                state.removeRemoteRecords(page.deletedIDs)
                for envelope in page.records {
                    guard envelope.schemaVersion == 1 else { throw CloudSyncError.invalidData }
                    if let revision = envelope.revision {
                        guard envelope.backup == nil,
                              envelope.payload.map(CloudSyncRevision.hash) == revision.digest else {
                            throw CloudSyncError.invalidData
                        }
                        if let data = envelope.payload {
                            _ = try await files.cachePayload(data, sensitive: revision.key.hasPrefix("provider/"))
                        }
                        try state.receive(revision)
                        state.fullFetchSeenIDs?.insert(revision.id)
                    } else if let backup = envelope.backup {
                        guard UUID(uuidString: backup.id) != nil,
                              envelope.payload == nil,
                              backup.heads.keys.allSatisfy(CloudSyncScope.accepts),
                              backup.heads.values.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw CloudSyncError.invalidData }
                        state.backups[backup.id] = backup
                        state.uploaded.insert(backup.id)
                        state.fullFetchSeenIDs?.insert(backup.id)
                    } else { throw CloudSyncError.invalidData }
                }
                if !page.moreComing, let known = state.fullFetchKnownIDs, let seen = state.fullFetchSeenIDs {
                    state.removeRemoteRecords(known.subtracting(seen))
                    state.fullFetchKnownIDs = nil
                    state.fullFetchSeenIDs = nil
                }
                state.changeToken = page.token
                // Persist blobs and revisions before advancing the token.
                try await persist(state)
                more = page.moreComing
            }

            // Network I/O may have suspended while the user changed local data.
            // Capture those edits with a newer clock before selecting winners.
            try await captureLocalChanges(into: &state)
            // Retention always preserves cloud winners. If an external tool
            // removed the winner itself, preserve local data with a fresh ID;
            // never publish a checkpoint referring to a missing cloud record.
            for (key, id) in state.localHeads where (state.retiredLocalRevisions ?? []).contains(id) {
                if state.winningHeads[key]?.id == id, let revision = state.revisions[id] {
                    _ = try state.recordLocal(key: key, data: try await payload(revision), force: true)
                }
            }
            if !state.localHeads.isEmpty && Set(state.localHeads.values).isDisjoint(with: state.retiredLocalRevisions ?? [])
                && !state.backups.values.contains(where: { $0.heads == state.localHeads }) {
                let checkpoint = makeBackup(state)
                state.backups[checkpoint.id] = checkpoint
            }
            try await persist(state)
            for (key, winner) in state.winningHeads.sorted(by: { $0.key < $1.key }) {
                try checkCanContinue()
                guard state.localHeads[key] != winner.id else { continue }
                let data = try await payload(winner)
                let expected = state.localHeads[key].flatMap { state.revisions[$0]?.digest } ?? initialDefaultDigests[key]
                guard try await apply(key: key, data: data, expectedDigest: expected) else { throw CloudSyncError.busy }
                state.localHeads[key] = winner.id
                requiresRefresh = true
                try await persist(state)
            }
            if requiresRefresh {
                try checkCanContinue()
                await didImportChanges()
                requiresRefresh = false
            }

            state.discardRetiredLocalRevisions()
            try await persist(state)

            for revision in state.revisions.values.sorted(by: { $0.precedes($1) }) where !state.uploaded.contains(revision.id) {
                try checkCanContinue()
                guard try await transport.accountID() == account else { throw CloudSyncError.accountChanged }
                try await transport.upload(CloudSyncEnvelope(revision: revision, payload: try await payload(revision)))
                state.uploaded.insert(revision.id)
                try await persist(state)
            }
            // Every changed synchronized state is also a recoverable checkpoint.
            if !state.localHeads.isEmpty && !state.backups.values.contains(where: { $0.heads == state.localHeads }) {
                let backup = makeBackup(state)
                state.backups[backup.id] = backup
                try await persist(state)
            }
            for backup in state.backups.values.sorted(by: { $0.date < $1.date }) where !state.uploaded.contains(backup.id) {
                // A queued offline checkpoint may reference history already
                // pruned by a peer. Never publish a partially restorable backup.
                guard backup.heads.allSatisfy({ state.revisions[$0.value]?.key == $0.key }) else {
                    state.backups.removeValue(forKey: backup.id)
                    continue
                }
                try checkCanContinue()
                guard try await transport.accountID() == account else { throw CloudSyncError.accountChanged }
                try await transport.upload(CloudSyncEnvelope(backup: backup))
                state.uploaded.insert(backup.id)
                try await persist(state)
            }
            try await pruneHistory(state: &state, account: account)
            try checkCanContinue()
            lastSyncDate = .now
            defaults.set(lastSyncDate, forKey: "via-vera.icloud-last-sync")
            statusMessage = String(localized: "已同步，历史版本已备份。")
        } catch is CancellationError {
            statusMessage = String(localized: "同步已暂停，稍后会自动重试。")
        } catch CloudSyncError.busy {
            statusMessage = CloudSyncError.busy.localizedDescription
        } catch CloudSyncError.cloudBusy {
            statusMessage = CloudSyncError.cloudBusy.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = String(localized: "同步未完成，本机数据已保留。")
        }
        if acquiredSession { await transport.endSession() }
    }

    /// Restore replaces only keys present in the selected checkpoint. Newer
    /// unrelated conversations/files survive. The pre-restore state is retained.
    func restore(_ backup: CloudSyncBackup) async {
        guard !isSyncing, isEnabled, canApplyChanges(), var state = index else { return }
        isSyncing = true
        backgroundExpired = false
        errorMessage = nil
        let lease = BackgroundExecutionController.shared.begin { [weak self] in self?.backgroundExpired = true }
        defer {
            BackgroundExecutionController.shared.end(lease)
            isSyncing = false
        }
        do {
            guard try await transport.accountID() == state.accountID else { throw CloudSyncError.accountChanged }
            try await captureLocalChanges(into: &state)
            // A device may restore while offline from a peer's cleanup. Give
            // the safety copy fresh IDs, rather than referencing retired ones.
            for (key, id) in state.localHeads.sorted(by: { $0.key < $1.key }) {
                guard let revision = state.revisions[id] else { throw CloudSyncError.invalidData }
                _ = try state.recordLocal(key: key, data: try await payload(revision), force: true)
            }
            let safety = makeBackup(state)
            state.backups[safety.id] = safety
            try await persist(state)
            // Validate the entire checkpoint before applying any of it.
            for (key, id) in backup.heads {
                guard let revision = state.revisions[id], revision.key == key else { throw CloudSyncError.invalidData }
                _ = try await payload(revision)
            }
            for (key, id) in backup.heads.sorted(by: { $0.key < $1.key }) {
                try checkCanContinue()
                guard let revision = state.revisions[id] else { throw CloudSyncError.invalidData }
                let data = try await payload(revision)
                let expected = state.localHeads[key].flatMap { state.revisions[$0]?.digest } ?? initialDefaultDigests[key]
                guard try await apply(key: key, data: data, expectedDigest: expected) else { throw CloudSyncError.busy }
                requiresRefresh = true
                // Restoring is an explicit new edit, even when the bytes match
                // the current local copy but a newer remote version is pending.
                _ = try state.recordLocal(key: key, data: data, force: true)
                try await persist(state)
            }
            await didImportChanges()
            requiresRefresh = false
            statusMessage = String(localized: "备份已恢复，其他内容已保留。")
            requestSync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkCanContinue() throws {
        try Task.checkCancellation()
        guard isEnabled, !backgroundExpired else { throw CancellationError() }
        guard canApplyChanges(), editingSettings.isEmpty else { throw CloudSyncError.busy }
    }

    private func captureLocalChanges(into state: inout CloudSyncIndex) async throws {
        try checkCanContinue()
        var documents = try conversations.syncDocuments()
        documents.merge(try await providers.syncDocuments(keychain: keychain)) { _, new in new }
        if let preference = try preferences.syncData() { documents["preference/model"] = preference }
        var digests = try await files.documentDigests()
        for (key, data) in documents {
            digests[key] = try await files.cachePayload(data, sensitive: key.hasPrefix("provider/"))
        }
        try checkCanContinue()
        initialDefaultDigests = [:]
        for key in Set(digests.keys).union(state.localHeads.keys).sorted() {
            guard CloudSyncScope.accepts(key) else { throw CloudSyncError.invalidData }
            let digest = digests[key]
            // A fresh install seeds these files before it can contact iCloud.
            // They are placeholders, not user edits that should win a merge.
            // Once a key has a baseline, resetting it to default IS a real edit.
            if state.localHeads[key] == nil, let digest, isInitialDefault(key: key, digest: digest) {
                initialDefaultDigests[key] = digest
                continue
            }
            if let id = state.localHeads[key], state.revisions[id]?.digest == digest { continue }
            // Upgrade metadata-only clients without interpreting their missing
            // API key as a request to erase another device's credential.
            if key.hasPrefix("provider/"), let data = documents[key],
               let document = try? JSONDecoder().decode(CloudSyncProviderDocument.self, from: data),
               document.credential == nil, let id = state.localHeads[key],
               let previous = state.revisions[id], let oldData = try await payload(previous),
               let oldProfile = try? JSONDecoder().decode(ProviderProfile.self, from: oldData),
               oldProfile == document.profile { continue }
            _ = try state.recordLocal(key: key, digest: digest)
        }
    }

    private func isInitialDefault(key: String, digest: String) -> Bool {
        switch key {
        case "control/agent/SOUL.md": digest == CloudSyncRevision.hash(Data(SoulStore.defaultSoul.utf8))
        case "control/memory/MEMORY.md": digest == CloudSyncRevision.hash(Data("# Long-term memory\n\n".utf8))
        case "control/memory/HARNESS_ERRORS.md": digest == CloudSyncRevision.hash(Data("# Harness failures\n\n".utf8))
        default: false
        }
    }

    private func payload(_ revision: CloudSyncRevision) async throws -> Data? {
        guard let digest = revision.digest else { return nil }
        return try await files.payload(digest)
    }

    private func apply(key: String, data: Data?, expectedDigest: String?) async throws -> Bool {
        try checkCanContinue()
        if key.hasPrefix("conversation/") {
            return try conversations.applySyncDocument(key: key, data: data, expectedDigest: expectedDigest)
        }
        if key.hasPrefix("provider/") {
            return try await providers.applySyncDocument(key: key, data: data, expectedDigest: expectedDigest, keychain: keychain)
        }
        if key == "preference/model" { return try preferences.applySyncData(data, expectedDigest: expectedDigest) }
        return try await files.apply(key: key, data: data, expectedDigest: expectedDigest)
    }

    private func persist(_ state: CloudSyncIndex) async throws {
        try await files.saveIndex(state)
        index = state
        backups = state.backups.values.filter { backup in
            backup.heads.allSatisfy { key, id in state.revisions[id]?.key == key }
        }.sorted { $0.date > $1.date }
    }

    private func makeBackup(_ state: CloudSyncIndex) -> CloudSyncBackup {
        CloudSyncBackup(id: UUID().uuidString, date: .now,
                        deviceName: ProcessInfo.processInfo.hostName,
                        heads: state.localHeads)
    }

    private func pruneHistory(state: inout CloudSyncIndex, account: String) async throws {
        // Delete manifests before their unreachable versions. Each batch is
        // fenced by the CloudKit lease, including retries after app termination.
        try await deleteHistory(CloudSyncRetention.expiredBackups(in: state), state: &state, account: account)
        try await deleteHistory(CloudSyncRetention.unusedRevisions(in: state), state: &state, account: account)
        try await files.removeUnusedPayloads(retaining: state)
    }

    private func deleteHistory(_ ids: [String], state: inout CloudSyncIndex, account: String) async throws {
        for start in stride(from: 0, to: ids.count, by: 100) {
            try checkCanContinue()
            guard try await transport.accountID() == account else { throw CloudSyncError.accountChanged }
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            try await transport.deleteRecords(batch)
            state.removeRemoteRecords(batch)
            try await persist(state)
        }
    }
}
