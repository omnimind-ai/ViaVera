import Foundation
import SwiftData
import Testing
@testable import Via_Vera

@Suite("App model selection")
@MainActor
struct AppModelSelectionTests {
    @Test("Tool creation opens an empty referenced chat without requiring a model or sending a message")
    func nativeToolComposerEntry() async throws {
        let suiteName = "NativeToolComposerEntryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let (model, container) = try await makeModel(
            directory: directory, defaults: defaults, withBuiltInSkills: true, withModels: false
        )
        defer { withExtendedLifetime(container) {} }
        model.newConversation()
        let ordinary = try #require(model.selectedConversation)
        model.chatDraft(for: ordinary.id).text = "Keep this draft"
        model.selectedTab = .tools
        try model.beginNativeToolConversation()
        let builder = try #require(model.selectedConversation)
        #expect(builder.id != ordinary.id)
        #expect(builder.messages.isEmpty)
        #expect(builder.modelID.isEmpty)
        #expect(model.chatCoordinator.busyConversationID == nil)
        let draft = model.chatDraft(for: builder.id)
        #expect(draft.text.isEmpty)
        #expect(draft.skillReference?.id == "native-tool-builder")
        #expect(draft.requestsFocus)
        #expect(model.destination == .conversation(builder.id))
#if os(iOS)
        #expect(model.selectedTab == .conversations)
        #expect(model.conversationPath == [builder.id])
#endif
        draft.text = "Build a checklist"
        model.newConversation()
        #expect(model.selectedConversation?.id == ordinary.id)
        #expect(model.chatDraft(for: ordinary.id).skillReference == nil)
        #expect(model.chatDraft(for: ordinary.id).text == "Keep this draft")
        #expect(model.chatDraft(for: builder.id) === draft)
        #expect(draft.text == "Build a checklist")
        let toolID = UUID()
        try model.beginNativeToolConversation(editing: toolID)
        let editing = try #require(model.selectedConversation)
        #expect(model.chatDraft(for: editing.id).skillReference?.context.contains(toolID.uuidString) == true)
        #expect(editing.messages.isEmpty)
    }

    @Test("Tool navigation preserves conversation identity and composer drafts")
    func toolNavigationPreservesChat() async throws {
        let suiteName = "ToolNavigationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let (model, container) = try await makeModel(directory: directory, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        #expect(model.selectedTab == .conversations)
        #expect(model.conversationPath.isEmpty)
        model.newConversation()
        let conversation = try #require(model.selectedConversation)
        let draft = model.chatDraft(for: conversation.id)
        draft.text = "Unsent message"
        let toolID = UUID()
        model.openNativeTool(toolID)
        #expect(model.selectedTab == .tools)
        #expect(model.nativeToolPath == [toolID])
        #expect(model.selectedConversation?.id == conversation.id)
        model.selectedTab = .conversations
        #expect(model.chatDraft(for: conversation.id) === draft)
        #expect(draft.text == "Unsent message")
#if os(iOS)
        #expect(model.conversationPath == [conversation.id])
        model.conversationPath = []
        #expect(model.destination == nil)
#endif
        await model.deleteConversation(conversation)
        #expect(model.nativeToolPath == [toolID])
    }

    @Test("Manual choices carry into new and reused drafts without changing history")
    func manualSelectionCarriesIntoNewConversations() async throws {
        let suiteName = "AppModelSelectionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let (model, container) = try await makeModel(directory: directory, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        model.newConversation()
        let first = try #require(model.selectedConversation)
        #expect(first.modelID == "first")
        try model.conversations.append(.user("History"), to: first)

        model.selectModel(providerID: "provider", modelID: "second", for: first)
        model.newConversation()
        let draft = try #require(model.selectedConversation)
        #expect(draft.id != first.id)
        #expect(draft.providerID == "provider")
        #expect(draft.modelID == "second")

        model.destination = .conversation(first.id)
        model.selectModel(providerID: "provider", modelID: "third", for: first)
        model.newConversation()
        #expect(model.selectedConversation?.id == draft.id)
        #expect(draft.modelID == "third")

        try model.conversations.append(.user("Second history"), to: draft)
        model.selectModel(providerID: "provider", modelID: "second", for: draft)
        model.destination = .conversation(first.id)
        model.newConversation()
        #expect(model.selectedConversation?.modelID == "second")
        #expect(first.modelID == "third")
        #expect(model.globalErrorMessage == nil)

        let reloadedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let (reloaded, reloadedContainer) = try await makeModel(
            directory: directory,
            defaults: reloadedDefaults
        )
        defer { withExtendedLifetime(reloadedContainer) {} }
        reloaded.newConversation()
        #expect(reloaded.selectedConversation?.providerID == "provider")
        #expect(reloaded.selectedConversation?.modelID == "second")
        #expect(reloaded.globalErrorMessage == nil)
    }

    private func makeModel(
        directory: URL,
        defaults: UserDefaults,
        withBuiltInSkills: Bool = false,
        withModels: Bool = true
    ) async throws -> (AppModel, ModelContainer) {
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let paths = WorkspacePaths(
            root: directory.appending(path: "workspace"),
            controlRoot: directory.appending(path: "control")
        )
        try paths.prepare()
        let providerStore = try ProviderStore(fileURL: paths.providerConfigFile)
        if withModels {
            try await providerStore.upsert(ProviderProfile(
                id: "provider",
                name: "Provider",
                baseURL: try #require(URL(string: "https://example.com/v1")),
                models: [ModelOption(id: "first"), ModelOption(id: "second"), ModelOption(id: "third")]
            ))
        }
        let runtimeState = directory.appending(path: "runtime")
        let model = AppModel(
            modelContext: container.mainContext,
            workspacePaths: paths,
            providerStore: providerStore,
            keychain: ModelSelectionTestKeychain(),
            alpineRuntime: AlpineRuntime(
                rootFileSystemArchiveURL: directory.appending(path: "unused.tar.gz"),
                stateDirectory: runtimeState,
                workspaceDirectory: paths.root
            ),
            alpineRootFileSystem: AlpineRootFileSystemManager(
                stateDirectory: runtimeState,
                resetRequestURL: directory.appending(path: "reset")
            ),
            toolActivity: ChatToolActivityModel(),
            toolExecutor: makeToolExecutor(paths: paths),
            browserSession: AppleBrowserSession(paths: paths),
            soulStore: SoulStore(paths: paths),
            memoryStore: MarkdownMemoryStore(paths: paths),
            skillStore: AgentSkillStore(
                paths: paths,
                builtInSkillsURL: withBuiltInSkills ? NativeToolTestFixtures.skillDirectory.deletingLastPathComponent() : nil
            ),
            appearanceStore: AppearanceSettingsStore(directoryURL: directory.appending(path: "appearance")),
            preferredModelStore: PreferredModelStore(defaults: defaults)
        )
        await model.providerSettings.load()
        await model.skillSettings.load()
        return (model, container)
    }
}

nonisolated private struct ModelSelectionTestKeychain: APIKeyStoring {
    func saveAPIKey(_ apiKey: String, for providerID: String) throws {}
    func apiKey(for providerID: String) throws -> String? { nil }
    func deleteAPIKey(for providerID: String) throws {}
    func saveEndpointBinding(_ endpointIdentity: String, for providerID: String) throws {}
    func endpointBinding(for providerID: String) throws -> String? { nil }
    func deleteEndpointBinding(for providerID: String) throws {}
}
