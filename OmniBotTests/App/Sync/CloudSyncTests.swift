import Foundation
import SwiftData
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
                              paths: paths, transport: cloud, defaults: defaults)
    }

    func newSync(cloud: TestCloudTransport) -> CloudSyncModel {
        CloudSyncModel(conversations: repository, providers: providers, preferences: preferences,
                       paths: paths, transport: cloud, defaults: defaults)
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
    func switchAccount() { account = "second-account"; records = [] }
    func resetZone() { records = []; shouldResetUploads = true }
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
        return CloudSyncPage(records: Array(records.dropFirst(reset ? 0 : offset)), token: Data(String(records.count).utf8),
                             moreComing: false, resetUploadState: reset)
    }

    func upload(_ envelope: CloudSyncEnvelope) throws {
        if failUploads { throw URLError(.notConnectedToInternet) }
        let id = envelope.revision?.id ?? envelope.backup?.id
        if !records.contains(where: { ($0.revision?.id ?? $0.backup?.id) == id }) { records.append(envelope) }
    }
}
