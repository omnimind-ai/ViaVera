import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Via_Vera

@Suite("iCloud sync", .serialized)
@MainActor
struct CloudSyncTests {
    @Test("SHA256 is canonical and does not collide on short hex bytes")
    func canonicalDigest() {
        #expect(CloudSyncRevision.hash(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Concurrent versions converge regardless of delivery order, with history retained")
    func concurrentConvergence() throws {
        var a = CloudSyncIndex()
        var b = CloudSyncIndex()
        let key = "control/agent/SOUL.md"
        let leftValue = try a.recordLocal(key: key, data: Data("left".utf8))
        let rightValue = try b.recordLocal(key: key, data: Data("right".utf8))
        let left = try #require(leftValue)
        let right = try #require(rightValue)
        try a.receive(right)
        try b.receive(left)
        #expect(a.winningHeads == b.winningHeads)
        #expect(a.revisions.count == 2)
        #expect(b.revisions.count == 2)
    }

    @Test("Deletion tombstones survive late old updates and unchanged scans")
    func deletionDoesNotResurrect() throws {
        var state = CloudSyncIndex()
        let key = "control/memory/MEMORY.md"
        let originalValue = try state.recordLocal(key: key, data: Data("remember".utf8))
        let original = try #require(originalValue)
        let unchanged = try state.recordLocal(key: key, data: Data("remember".utf8))
        #expect(unchanged == nil)
        let deletedValue = try state.recordLocal(key: key, data: nil)
        let deleted = try #require(deletedValue)
        try state.receive(original)
        #expect(state.winningHeads[key] == deleted)
        let stillDeleted = try state.recordLocal(key: key, data: nil)
        #expect(stillDeleted == nil)
        #expect(state.revisions.count == 2)
    }

    @Test("Sync scope excludes credentials, runtime state and path traversal")
    func scopeBoundary() {
        for key in ["control/../secret", "control/agent/providers.json", "control/agent/alarms.json",
                    "attachment/../outside", "attachment//x", "/etc/passwd", "control/native-tools/secrets.json",
                    "control/appearance/../../api-key", "preference/permissions"] {
            #expect(!CloudSyncScope.accepts(key))
        }
        for key in ["control/agent/SOUL.md", "control/skills/test/SKILL.md", "attachment/images/a.png",
                    "control/memory/short-memories/2026-09-29.md", "preference/model"] {
            #expect(CloudSyncScope.accepts(key))
        }
    }

    @Test("Two devices exchange chat payloads, providers and attachments, then propagate deletion")
    func crossDeviceRoundTrip() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        let conversation = try a.repository.createConversation(providerID: "service", modelID: "model")
        try a.repository.append(.user("Question"), to: conversation)
        let call = AgentToolCall(id: "tool-1", name: "file_read", arguments: "{}")
        try a.repository.append(.assistant("Answer", reasoningContent: "Reasoning", toolCalls: [call]), to: conversation)
        try a.repository.append(.tool(callID: call.id, name: call.name, content: "result"), to: conversation)
        let provider = ProviderProfile(id: "service", name: "Service", baseURL: URL(string: "https://example.com/v1")!)
        try await a.providers.upsert(provider)
        try Data([1, 2, 3]).write(to: a.paths.attachmentsDirectory.appending(path: "image.png"))
        await a.sync.synchronize()
        #expect(a.sync.errorMessage == nil)
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
        let restored = try #require(b.repository.conversation(id: conversation.id))
        #expect(try b.repository.transcript(for: restored) == a.repository.transcript(for: conversation))
        #expect(try Data(contentsOf: b.paths.attachmentsDirectory.appending(path: "image.png")) == Data([1, 2, 3]))
        #expect(await b.providers.profile(id: "service") == provider)
        try a.repository.delete(conversation)
        await a.sync.synchronize()
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
        #expect(b.repository.conversation(id: conversation.id) == nil)
    }

    @Test("Editing an existing transcript updates unique message IDs in place")
    func updatedTranscript() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        let conversation = try a.repository.createConversation(providerID: nil, modelID: "model")
        let user = AgentMessage.user("Original")
        try a.repository.append(user, to: conversation)
        try a.repository.append(.assistant("Old reply"), to: conversation)
        await a.sync.synchronize()
        await b.sync.synchronize()
        _ = try a.repository.replaceLatestUserTurn(messageID: user.id, with: "Edited", in: conversation)
        await a.sync.synchronize()
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
        let restored = try #require(b.repository.conversation(id: conversation.id))
        #expect(restored.messages.count == 1)
        #expect(restored.messages.first?.id == user.id)
        #expect(restored.messages.first?.content == "Edited")
    }

    @Test("Offline uploads retry after relaunch without losing local revisions")
    func retryAcrossRelaunch() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        let conversation = try a.repository.createConversation(providerID: nil, modelID: "model")
        try a.repository.append(.user("Offline work"), to: conversation)
        await cloud.setFailUploads(true)
        await a.sync.synchronize()
        #expect(a.sync.errorMessage != nil)
        #expect(a.repository.conversations.count == 1)
        await cloud.setFailUploads(false)
        let restarted = a.newSync(cloud: cloud)
        await restarted.synchronize()
        #expect(restarted.errorMessage == nil)
        await b.sync.synchronize()
        #expect(b.repository.conversation(id: conversation.id)?.messages.first?.content == "Offline work")
    }

    @Test("Restore preserves new conversations and keeps the pre-restore version")
    func restoreKeepsNewWork() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        defer { a.cleanUp() }
        let conversation = try a.repository.createConversation(providerID: nil, modelID: "model")
        let user = AgentMessage.user("Earlier")
        try a.repository.append(user, to: conversation)
        await a.sync.synchronize()
        let earlier = try #require(a.sync.backups.first)
        _ = try a.repository.replaceLatestUserTurn(messageID: user.id, with: "Later", in: conversation)
        let other = try a.repository.createConversation(providerID: nil, modelID: "model")
        try a.repository.append(.user("Keep me"), to: other)
        await a.sync.synchronize()
        await a.sync.restore(earlier)
        #expect(a.sync.errorMessage == nil)
        #expect(a.repository.conversation(id: conversation.id)?.messages.first?.content == "Earlier")
        #expect(a.repository.conversation(id: other.id)?.messages.first?.content == "Keep me")
        #expect(a.sync.backups.count >= 2)
    }

    @Test("Account switches pause before uploading any previous-account data")
    func accountSwitchPauses() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        defer { a.cleanUp() }
        let conversation = try a.repository.createConversation(providerID: nil, modelID: "model")
        try a.repository.append(.user("Private"), to: conversation)
        await a.sync.synchronize()
        await cloud.switchAccount()
        await a.sync.synchronize()
        #expect(a.sync.errorMessage == CloudSyncError.accountChanged.localizedDescription)
        #expect(await cloud.recordCount() == 0)
        #expect(a.repository.conversation(id: conversation.id) != nil)
    }

    @Test("Busy task or settings editor defers all cloud access")
    func busyDefersSync() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        defer { a.cleanUp() }
        a.sync.canApplyChanges = { false }
        await a.sync.synchronize()
        #expect(await cloud.accessCount() == 0)
        a.sync.canApplyChanges = { true }
        a.sync.editingSettings.insert("providers")
        await a.sync.synchronize()
        #expect(await cloud.accessCount() == 0)
    }

    @Test("Local edits made during a cloud fetch survive and reach the next device")
    func editDuringFetch() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        let conversation = try a.repository.createConversation(providerID: nil, modelID: "model")
        try a.repository.append(.user("Original"), to: conversation)
        await a.sync.synchronize()
        await cloud.pauseNextFetch()
        let task = Task { await a.sync.synchronize() }
        await cloud.waitUntilFetchPauses()
        try a.repository.rename(conversation, to: "Edited during network wait")
        await cloud.resumeFetch()
        await task.value
        await b.sync.synchronize()
        #expect(a.sync.errorMessage == nil)
        #expect(b.repository.conversation(id: conversation.id)?.title == "Edited during network wait")
    }

    @Test("Corrupt remote payloads never replace local data")
    func rejectsCorruptCloudPayload() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        defer { a.cleanUp() }
        try Data("local".utf8).write(to: a.paths.soulFile)
        await a.sync.synchronize()
        let revision = CloudSyncRevision(id: UUID().uuidString, key: "control/agent/SOUL.md",
                                         deviceID: UUID().uuidString, counter: 1_000, date: .now,
                                         digest: CloudSyncRevision.hash(Data("expected".utf8)))
        try await cloud.upload(CloudSyncEnvelope(revision: revision, payload: Data("corrupt".utf8)))
        await a.sync.synchronize()
        #expect(a.sync.errorMessage == CloudSyncError.invalidData.localizedDescription)
        #expect(try Data(contentsOf: a.paths.soulFile) == Data("local".utf8))
    }

    @Test("Fresh-device Soul and Memory defaults cannot overwrite existing cloud content")
    func freshDefaultsDoNotWin() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        try Data("Custom identity".utf8).write(to: a.paths.soulFile)
        try Data("User memories".utf8).write(to: a.paths.longTermMemoryFile)
        await a.sync.synchronize()
        try Data(SoulStore.defaultSoul.utf8).write(to: b.paths.soulFile)
        try Data("# Long-term memory\n\n".utf8).write(to: b.paths.longTermMemoryFile)
        var fresh = CloudSyncIndex()
        fresh.deviceID = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        try await CloudSyncFileStore(paths: b.paths).saveIndex(fresh)
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
        #expect(try Data(contentsOf: b.paths.soulFile) == Data("Custom identity".utf8))
        #expect(try Data(contentsOf: b.paths.longTermMemoryFile) == Data("User memories".utf8))
        await a.sync.synchronize()
        #expect(try Data(contentsOf: a.paths.soulFile) == Data("Custom identity".utf8))
    }

    @Test("A deleted cloud zone can be rebuilt from the durable local journal")
    func rebuildCloudZone() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        let conversation = try a.repository.createConversation(providerID: nil, modelID: "model")
        try a.repository.append(.user("Durable"), to: conversation)
        await a.sync.synchronize()
        await cloud.resetZone()
        await a.sync.synchronize()
        #expect(a.sync.errorMessage == nil)
        await b.sync.synchronize()
        #expect(b.repository.conversation(id: conversation.id)?.messages.first?.content == "Durable")
    }

    @Test("Provider keys sync, rotate, restore and delete without plaintext local copies")
    func providerCredentialsRoundTrip() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        let profile = ProviderProfile(id: "credential-test", name: "Example", baseURL: URL(string: "https://example.com")!)
        try await a.providers.upsert(profile)
        try a.keychain.saveAPIKey("test-key-first-version", for: profile.id)
        a.keychain.saveEndpointBinding(ProviderEndpointIdentity.canonical(for: profile), for: profile.id)
        await a.sync.synchronize()
        let first = try #require(a.sync.backups.first)
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
        #expect(b.keychain.apiKey(for: profile.id) == "test-key-first-version")
        #expect(b.keychain.endpointBinding(for: profile.id) == ProviderEndpointIdentity.canonical(for: profile))

        // Inspect only the test fixture: neither providers.json nor cached
        // backup objects contain the synthetic key as UTF-8 or base64 JSON.
        let enumerator = try #require(FileManager.default.enumerator(at: b.paths.controlRoot, includingPropertiesForKeys: [.isRegularFileKey]))
        for url in enumerator.allObjects.compactMap({ $0 as? URL }) {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let bytes = try Data(contentsOf: url)
            #expect(bytes.range(of: Data("test-key-first-version".utf8)) == nil)
            #expect(bytes.range(of: Data(Data("test-key-first-version".utf8).base64EncodedString().utf8)) == nil)
        }
        try a.keychain.saveAPIKey("test-key-rotated-version", for: profile.id)
        await a.sync.synchronize()
        await b.sync.synchronize()
        #expect(b.keychain.apiKey(for: profile.id) == "test-key-rotated-version")
        await a.sync.restore(first)
        #expect(a.sync.errorMessage == nil)
        #expect(a.keychain.apiKey(for: profile.id) == "test-key-first-version")
        await a.sync.synchronize()
        await b.sync.synchronize()
        #expect(b.keychain.apiKey(for: profile.id) == "test-key-first-version")
        a.keychain.deleteAPIKey(for: profile.id)
        a.keychain.deleteEndpointBinding(for: profile.id)
        await a.sync.synchronize()
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
        #expect(b.keychain.apiKey(for: profile.id) == nil)
        #expect(b.keychain.endpointBinding(for: profile.id) == nil)
    }

    @Test("Legacy backups preserve matching keys and reject credential endpoint substitution")
    func legacyProviderAndInvalidBinding() async throws {
        let a = try SyncFixture(cloud: TestCloudTransport())
        defer { a.cleanUp() }
        let profile = ProviderProfile(id: "legacy", name: "Original", baseURL: URL(string: "https://example.com")!)
        try await a.providers.upsert(profile)
        try a.keychain.saveAPIKey("test-legacy-key", for: profile.id)
        a.keychain.saveEndpointBinding(ProviderEndpointIdentity.canonical(for: profile), for: profile.id)
        let store = a.providers
        let before = try #require(await store.syncDocuments(keychain: a.keychain)["provider/legacy"])
        var renamed = profile
        renamed.name = "Restored name"
        #expect(try await store.applySyncDocument(key: "provider/legacy", data: CloudSyncCoding.encode(renamed),
                                      expectedDigest: CloudSyncRevision.hash(before), keychain: a.keychain))
        #expect(a.keychain.apiKey(for: profile.id) == "test-legacy-key")
        let current = try #require(await store.syncDocuments(keychain: a.keychain)["provider/legacy"])
        var wrongEndpoint = profile
        wrongEndpoint.baseURL = URL(string: "https://different.example")!
        let invalid = CloudSyncProviderDocument(profile: wrongEndpoint,
            credential: .init(apiKey: "test-legacy-key", endpointBinding: ProviderEndpointIdentity.canonical(for: profile)))
        await #expect(throws: (any Error).self) {
            try await store.applySyncDocument(key: "provider/legacy", data: CloudSyncCoding.encode(invalid),
                                  expectedDigest: CloudSyncRevision.hash(current), keychain: a.keychain)
        }
        #expect(await a.providers.profile(id: profile.id) == renamed)
        #expect(a.keychain.apiKey(for: profile.id) == "test-legacy-key")
    }

    @Test("Keychain write failures roll back metadata and never rebind an old secret")
    func credentialFailureRollback() async throws {
        let a = try SyncFixture(cloud: TestCloudTransport())
        defer { a.cleanUp() }
        let profile = ProviderProfile(id: "failure", name: "Original", baseURL: URL(string: "https://example.com")!)
        try await a.providers.upsert(profile)
        try a.keychain.saveAPIKey("test-old-key", for: profile.id)
        a.keychain.saveEndpointBinding(ProviderEndpointIdentity.canonical(for: profile), for: profile.id)
        let store = a.providers
        let before = try #require(await store.syncDocuments(keychain: a.keychain)["provider/failure"])
        var changed = profile
        changed.baseURL = URL(string: "https://new.example")!
        let incoming = CloudSyncProviderDocument(profile: changed,
            credential: .init(apiKey: "test-new-key", endpointBinding: ProviderEndpointIdentity.canonical(for: changed)))
        a.keychain.failNextSave(for: profile.id)
        await #expect(throws: (any Error).self) {
            try await store.applySyncDocument(key: "provider/failure", data: CloudSyncCoding.encode(incoming),
                                  expectedDigest: CloudSyncRevision.hash(before), keychain: a.keychain)
        }
        #expect(await a.providers.profile(id: profile.id) == profile)
        #expect(a.keychain.apiKey(for: profile.id) == "test-old-key")
        #expect(a.keychain.endpointBinding(for: profile.id) == ProviderEndpointIdentity.canonical(for: profile))
    }

    @Test("Retention removes old cloud payloads; offline and expired-token clients cannot resurrect them")
    func retentionAndOfflineClient() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        let c = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp(); c.cleanUp() }
        try Data("version-0".utf8).write(to: a.paths.soulFile)
        await a.sync.synchronize()
        await b.sync.synchronize()
        await c.sync.synchronize()
        for version in 1...55 {
            try Data("version-\(version)".utf8).write(to: a.paths.soulFile)
            await a.sync.synchronize()
            #expect(a.sync.errorMessage == nil)
        }
        #expect(a.sync.backups.count == 50)
        let records = await cloud.allRecords()
        #expect(records.compactMap(\.backup).count == 50)
        #expect(records.compactMap(\.revision).count == 50)
        let cache = a.paths.controlRoot.appending(path: "CloudSync/objects")
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count == 50)
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
        #expect(try Data(contentsOf: b.paths.soulFile) == Data("version-55".utf8))
        await cloud.expireNextToken()
        await c.sync.synchronize()
        #expect(c.sync.errorMessage == nil)
        #expect(try Data(contentsOf: c.paths.soulFile) == Data("version-55".utf8))
        #expect(await cloud.recordCount() == records.count)
        // Every retained backup remains restorable after garbage collection.
        let oldest = try #require(c.sync.backups.last)
        await c.sync.restore(oldest)
        #expect(c.sync.errorMessage == nil)
        #expect(try Data(contentsOf: c.paths.soulFile) == Data("version-6".utf8))
    }

    @Test("Age retention always retains the latest backup and live deletion markers")
    func retentionBoundaries() throws {
        var state = CloudSyncIndex()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for day in 0..<35 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            let recorded = try state.recordLocal(key: "control/agent/SOUL.md", data: Data("\(day)".utf8), date: date)
            let revision = try #require(recorded)
            let backup = CloudSyncBackup(id: UUID().uuidString, date: date, deviceName: "Test", heads: state.localHeads)
            state.backups[backup.id] = backup
            state.uploaded.formUnion([backup.id, revision.id])
        }
        #expect(CloudSyncRetention.expiredBackups(in: state, now: now).count == 4)
        #expect(CloudSyncRetention.expiredBackups(in: state, now: now.addingTimeInterval(100 * 86_400)).count == 34)
        let deletion = try state.recordLocal(key: "control/agent/SOUL.md", data: nil)
        let tombstone = try #require(deletion)
        state.uploaded.insert(tombstone.id)
        state.backups.removeAll()
        #expect(!CloudSyncRetention.unusedRevisions(in: state).contains(tombstone.id))
    }

    @Test("Another device waits while a sync session is fetching")
    func serializesCloudSessions() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        let b = try SyncFixture(cloud: cloud)
        defer { a.cleanUp(); b.cleanUp() }
        await cloud.pauseNextFetch()
        let task = Task { await a.sync.synchronize() }
        await cloud.waitUntilFetchPauses()
        await b.sync.synchronize()
        #expect(b.sync.statusMessage == CloudSyncError.cloudBusy.localizedDescription)
        await cloud.resumeFetch()
        await task.value
        await b.sync.synchronize()
        #expect(b.sync.errorMessage == nil)
    }

    @Test("Interrupted cleanup retries without losing the current version or retained backups")
    func failedCleanupRetries() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        defer { a.cleanUp() }
        for version in 0..<50 {
            try Data("before-\(version)".utf8).write(to: a.paths.soulFile)
            await a.sync.synchronize()
        }
        await cloud.setFailDeletes(true)
        try Data("latest-after-failure".utf8).write(to: a.paths.soulFile)
        await a.sync.synchronize()
        #expect(a.sync.errorMessage != nil)
        #expect(a.sync.backups.count == 51)
        #expect(try Data(contentsOf: a.paths.soulFile) == Data("latest-after-failure".utf8))
        await cloud.setFailDeletes(false)
        let restarted = a.newSync(cloud: cloud)
        await restarted.synchronize()
        #expect(restarted.errorMessage == nil)
        #expect(restarted.backups.count == 50)
        let records = await cloud.allRecords()
        let revisions = Dictionary(uniqueKeysWithValues: records.compactMap(\.revision).map { ($0.id, $0) })
        #expect(records.compactMap(\.backup).allSatisfy { backup in
            backup.heads.allSatisfy { revisions[$0.value]?.key == $0.key }
        })
        restarted.isEnabled = false
    }

    @Test("A local API key edit after capture prevents stale cloud replacement")
    func credentialCompareAndSet() async throws {
        let a = try SyncFixture(cloud: TestCloudTransport())
        defer { a.cleanUp() }
        let profile = ProviderProfile(id: "edited-key", name: "Example", baseURL: URL(string: "https://example.com")!)
        try await a.providers.upsert(profile)
        try a.keychain.saveAPIKey("test-before", for: profile.id)
        a.keychain.saveEndpointBinding(ProviderEndpointIdentity.canonical(for: profile), for: profile.id)
        let captured = try #require(await a.providers.syncDocuments(keychain: a.keychain)["provider/edited-key"])
        try a.keychain.saveAPIKey("test-local-edit", for: profile.id)
        #expect(try await !a.providers.applySyncDocument(key: "provider/edited-key", data: captured,
            expectedDigest: CloudSyncRevision.hash(captured), keychain: a.keychain))
        #expect(a.keychain.apiKey(for: profile.id) == "test-local-edit")
    }

    @Test("Encrypted provider cache survives relaunch and rejects tampering")
    func encryptedCacheIntegrity() async throws {
        let a = try SyncFixture(cloud: TestCloudTransport())
        defer { a.cleanUp() }
        let data = Data("synthetic-secret-payload".utf8)
        let cache = CloudSyncFileStore(paths: a.paths, keychain: a.keychain)
        let digest = try await cache.cachePayload(data, sensitive: true)
        let reopened = CloudSyncFileStore(paths: a.paths, keychain: a.keychain)
        #expect(try await reopened.payload(digest) == data)
        let url = a.paths.controlRoot.appending(path: "CloudSync/objects/\(digest).sealed")
        var sealed = try Data(contentsOf: url)
        sealed[sealed.count - 1] ^= 0xFF
        try sealed.write(to: url)
        await #expect(throws: (any Error).self) { try await reopened.payload(digest) }
    }

    @Test("File imports use compare-and-set and reject symlinks")
    func fileBoundary() async throws {
        let cloud = TestCloudTransport()
        let a = try SyncFixture(cloud: cloud)
        defer { a.cleanUp() }
        let store = CloudSyncFileStore(paths: a.paths)
        let original = Data("local edit".utf8)
        try original.write(to: a.paths.soulFile)
        #expect(try await !store.apply(key: "control/agent/SOUL.md", data: Data("remote".utf8), expectedDigest: nil))
        #expect(try Data(contentsOf: a.paths.soulFile) == original)
        let outside = a.root.appending(path: "outside")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: a.paths.attachmentsDirectory.appending(path: "link"), withDestinationURL: outside)
        await #expect(throws: (any Error).self) { try await store.documentDigests() }
        #expect(try Data(contentsOf: outside) == Data("secret".utf8))
    }
}

@MainActor
private final class SyncFixture {
    let root: URL
    let paths: WorkspacePaths
    let container: ModelContainer
    let repository: ConversationRepository
    let providers: ProviderStore
    let preferences: PreferredModelStore
    let defaults: UserDefaults
    let defaultsName: String
    let sync: CloudSyncModel
    let keychain = TestSyncKeychain()

    init(cloud: TestCloudTransport) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "OmniBotSyncTests-\(UUID().uuidString)")
        paths = WorkspacePaths(root: root.appending(path: "workspace"), controlRoot: root.appending(path: "control"))
        try paths.prepare()
        container = try ModelContainer(for: ConversationRecord.self, MessageRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        repository = ConversationRepository(modelContext: container.mainContext)
        providers = try ProviderStore(fileURL: paths.providerConfigFile)
        defaultsName = "OmniBotSyncTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.set(true, forKey: "via-vera.icloud-sync")
        preferences = PreferredModelStore(defaults: defaults)
        sync = CloudSyncModel(conversations: repository, providers: providers, preferences: preferences,
                              paths: paths, keychain: keychain, cacheKeychain: keychain, transport: cloud, defaults: defaults)
    }

    func newSync(cloud: TestCloudTransport) -> CloudSyncModel {
        CloudSyncModel(conversations: repository, providers: providers, preferences: preferences,
                       paths: paths, keychain: keychain, cacheKeychain: keychain, transport: cloud, defaults: defaults)
    }

    func cleanUp() {
        sync.isEnabled = false
        defaults.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor TestCloudTransport: CloudSyncTransport {
    private var account = "first-account"
    private var records: [CloudSyncEnvelope] = []
    private var events: [(id: String, deleted: Bool)] = []
    private var expireToken = false
    private var failDeletes = false
    private var sessionActive = false
    private var failUploads = false
    private var accesses = 0
    private var shouldResetUploads = false
    private var shouldPauseFetch = false
    private var pausedFetch: CheckedContinuation<Void, Never>?
    private var fetchWaiter: CheckedContinuation<Void, Never>?

    func accountID() -> String { accesses += 1; return account }
    func accessCount() -> Int { accesses }
    func recordCount() -> Int { records.count }
    func setFailUploads(_ value: Bool) { failUploads = value }
    func setFailDeletes(_ value: Bool) { failDeletes = value }
    func expireNextToken() { expireToken = true }
    func allRecords() -> [CloudSyncEnvelope] { records }
    func switchAccount() { account = "second-account"; records = []; events = [] }
    func resetZone() { records = []; events = []; shouldResetUploads = true }
    func beginSession() throws {
        guard !sessionActive else { throw CloudSyncError.cloudBusy }
        sessionActive = true
    }
    func endSession() { sessionActive = false }
    func pauseNextFetch() { shouldPauseFetch = true }
    func waitUntilFetchPauses() async {
        if pausedFetch != nil { return }
        await withCheckedContinuation { fetchWaiter = $0 }
    }
    func resumeFetch() { pausedFetch?.resume(); pausedFetch = nil }

    func fetch(since token: Data?) async throws -> CloudSyncPage {
        if shouldPauseFetch {
            shouldPauseFetch = false
            await withCheckedContinuation {
                pausedFetch = $0
                fetchWaiter?.resume()
                fetchWaiter = nil
            }
        }
        let offset = token.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        let reset = shouldResetUploads
        shouldResetUploads = false
        let full = reset || expireToken || token == nil
        expireToken = false
        let changes = events.dropFirst(full ? 0 : offset)
        let changed = Set(changes.filter { !$0.deleted }.map(\.id))
        return CloudSyncPage(records: records.filter { full || changed.contains($0.revision?.id ?? $0.backup!.id) },
                             token: Data(String(events.count).utf8), moreComing: false, resetUploadState: reset,
                             deletedIDs: full ? [] : changes.filter(\.deleted).map(\.id), beginsFullFetch: full)
    }

    func upload(_ envelope: CloudSyncEnvelope) throws {
        if failUploads { throw URLError(.notConnectedToInternet) }
        guard let id = envelope.revision?.id ?? envelope.backup?.id else { throw CloudSyncError.invalidData }
        if !records.contains(where: { ($0.revision?.id ?? $0.backup?.id) == id }) {
            records.append(envelope)
            events.append((id, false))
        }
    }

    func deleteRecords(_ ids: [String]) throws {
        if failDeletes { throw URLError(.notConnectedToInternet) }
        let removing = Set(ids)
        records.removeAll { removing.contains($0.revision?.id ?? $0.backup!.id) }
        events.append(contentsOf: ids.map { ($0, true) })
    }
}

nonisolated private final class TestSyncKeychain: APIKeyStoring, Sendable {
    private struct State {
        var keys: [String: String] = [:]
        var bindings: [String: String] = [:]
        var failedProvider: String?
    }
    private let state = Mutex(State())
    func failNextSave(for id: String) { state.withLock { $0.failedProvider = id } }
    func saveAPIKey(_ value: String, for id: String) throws {
        try state.withLock {
            if $0.failedProvider == id { $0.failedProvider = nil; throw CloudSyncError.credentialStorage }
            $0.keys[id] = value
        }
    }
    func apiKey(for id: String) -> String? { state.withLock { $0.keys[id] } }
    func deleteAPIKey(for id: String) { state.withLock { $0.keys[id] = nil } }
    func saveEndpointBinding(_ value: String, for id: String) { state.withLock { $0.bindings[id] = value } }
    func endpointBinding(for id: String) -> String? { state.withLock { $0.bindings[id] } }
    func deleteEndpointBinding(for id: String) { state.withLock { $0.bindings[id] = nil } }
}
