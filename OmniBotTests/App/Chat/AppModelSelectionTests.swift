import Foundation
import SwiftData
import Testing
@testable import Via_Vera

@Suite("App model selection")
@MainActor
struct AppModelSelectionTests {
    @Test("Modes keep history and drafts separate and persist the selected mode")
    func separateConversationModes() async throws {
        let suiteName = "ConversationModeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let (model, container) = try await makeModel(directory: directory, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        model.newConversation()
        let task = try #require(model.selectedConversation)
        model.chatDraft(for: task.id).text = "Task draft"
        model.selectConversationMode(.chat)
        model.newConversation()
        let chat = try #require(model.selectedConversation)
        #expect(chat.mode == .chat)
        #expect(chat.id != task.id)
        #expect(model.modeConversations.map(\.id) == [chat.id])
        model.chatDraft(for: chat.id).text = "Chat draft"
        model.selectConversationMode(.task)
        model.newConversation()
        #expect(model.selectedConversation?.id == task.id)
        #expect(model.chatDraft(for: task.id).text == "Task draft")
        model.selectConversationMode(.chat)
        model.newConversation()
        #expect(model.selectedConversation?.id == chat.id)
        #expect(model.chatDraft(for: chat.id).text == "Chat draft")
        #expect(defaults.string(forKey: "conversationMode") == "chat")
        // Direct navigation (including history) restores the conversation's mode.
        model.destination = .conversation(task.id)
        #expect(model.conversationMode == .task)
        model.destination = .conversation(chat.id)
        #expect(model.conversationMode == .chat)
        await model.deleteConversation(chat)
        #expect(model.conversationMode == .chat)
        #expect(model.modeConversations.allSatisfy { $0.mode == .chat })
        #expect(model.conversations.conversation(id: task.id) != nil)
    }

    @Test("Chat system prompt is independent and does not require a task workspace")
    func independentChatPrompt() async throws {
        let suiteName = "ChatPromptTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let (model, container) = try await makeModel(directory: directory, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        await model.soulSettings.save("TASK ONLY")
        await model.soulSettings.saveChat("Talk with me in a warm, concise voice.")
        let memoryStore = MarkdownMemoryStore(paths: model.workspacePaths)
        _ = try await memoryStore.upsertLongTermMemory("The user prefers concise Chinese answers.")
        let task = ConversationRecord(modelID: "model", mode: .task)
        let taskMessages = try await model.chatCoordinator.prepareSystemMessages(
            for: task, model: ModelOption(id: "model"), query: "answer preferences"
        )
        #expect(taskMessages.contains { $0.content?.contains("concise Chinese answers") == true })
        // A file in place of the workspace makes task preparation fail. Chat
        // can still read its host-only Soul and build a normal text request.
        try FileManager.default.removeItem(at: model.workspacePaths.root)
        try Data("unavailable workspace".utf8).write(to: model.workspacePaths.root)
        let chat = ConversationRecord(modelID: "model", mode: .chat)
        let messages = try await model.chatCoordinator.prepareSystemMessages(
            for: chat, model: ModelOption(id: "model", supportsTools: true)
        )
        #expect(messages.map(\.role) == [.system, .system])
        #expect(messages.first?.content == "Talk with me in a warm, concise voice.\n")
        #expect(messages.last?.content?.contains("concise Chinese answers") == true)
        #expect(!messages.contains { $0.content?.contains("TASK ONLY") == true })
        #expect(model.chatCoordinator.sharedMemory.errorMessage == nil)
        await model.soulSettings.saveChat("")
        let withoutSoul = try await model.chatCoordinator.prepareSystemMessages(
            for: chat, model: ModelOption(id: "model")
        )
        #expect(withoutSoul.count == 1)
        #expect(withoutSoul.first?.content?.contains("concise Chinese answers") == true)
    }

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

#if os(macOS)
    @Test("Switching modes focuses the selected conversation once and preserves drafts")
    func modeSwitchComposerFocus() async throws {
        let suiteName = "ModeSwitchFocusTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let (model, container) = try await makeModel(directory: directory, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        model.newConversation()
        let firstTask = try #require(model.selectedConversation)
        try model.conversations.append(.user("Earlier task"), to: firstTask)
        model.newConversation()
        let activeTask = try #require(model.selectedConversation)
        model.chatDraft(for: activeTask.id).text = "Keep task draft"
        #expect(model.modeSwitchFocusConversationID == nil)

        // An empty mode creates a conversation and targets its new composer.
        model.selectConversationMode(.chat)
        let chat = try #require(model.selectedConversation)
        #expect(chat.mode == .chat)
        #expect(model.modeSwitchFocusConversationID == chat.id)
        #expect(!model.consumeModeSwitchComposerFocus(for: activeTask.id))
        #expect(model.consumeModeSwitchComposerFocus(for: chat.id))
        #expect(!model.consumeModeSwitchComposerFocus(for: chat.id))
        model.chatDraft(for: chat.id).text = "Keep chat draft"

        // Return to the remembered task rather than another task in history.
        model.selectConversationMode(.task)
        #expect(model.destination == .conversation(activeTask.id))
        #expect(!model.consumeModeSwitchComposerFocus(for: firstTask.id))
        #expect(model.consumeModeSwitchComposerFocus(for: activeTask.id))
        #expect(model.chatDraft(for: activeTask.id).text == "Keep task draft")
        model.selectConversationMode(.task)
        #expect(model.modeSwitchFocusConversationID == nil)

        // Rapid switching replaces the pending target with the latest one.
        model.selectConversationMode(.chat)
        model.selectConversationMode(.task)
        #expect(!model.consumeModeSwitchComposerFocus(for: chat.id))
        #expect(model.consumeModeSwitchComposerFocus(for: activeTask.id))
        model.selectConversationMode(.chat)
        #expect(model.consumeModeSwitchComposerFocus(for: chat.id))
        #expect(model.chatDraft(for: chat.id).text == "Keep chat draft")

        // Navigating elsewhere cancels focus that has not been claimed yet.
        model.selectConversationMode(.task)
        model.openNativeToolLibrary()
        #expect(model.modeSwitchFocusConversationID == nil)
        #expect(!model.consumeModeSwitchComposerFocus(for: activeTask.id))
    }

    @Test("Window history restores tool screens and drafts while excluding the settings card")
    func windowNavigationHistory() async throws {
        let suiteName = "WindowNavigationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let (model, container) = try await makeModel(directory: directory, defaults: defaults)
        defer { withExtendedLifetime(container) {} }
        await model.nativeTools.load()
        let tool = try #require(model.nativeTools.records.first)
        model.newConversation()
        let conversation = try #require(model.selectedConversation)
        let draft = model.chatDraft(for: conversation.id)
        draft.text = "Keep my unsent message"
        #expect(!model.canGoBack)

        model.openNativeToolLibrary()
        model.openNativeTool(tool.id)
        let detail = model.navigationHistory.current
        if let screen = tool.package.screens.dropFirst().first {
            model.nativeToolScreenID = screen.id
            model.goBack()
            #expect(model.nativeToolScreenID == nil)
            model.goForward()
            #expect(model.nativeToolScreenID == screen.id)
            model.goBack()
        }
        model.goBack()
        #expect(model.destination == .tools)
        #expect(model.nativeToolPath.isEmpty)
        model.goForward()
        #expect(model.navigationHistory.current == detail)
        #expect(model.nativeToolPath == [tool.id])

        model.presentSettings(.appearance)
        #expect(!model.canGoBack)
        #expect(!model.canGoForward)
        model.goBack()
        #expect(model.navigationHistory.current == detail)
        model.dismissSettings()
        model.goBack()
        model.goBack()
        #expect(model.destination == .conversation(conversation.id))
        #expect(model.chatDraft(for: conversation.id) === draft)
        #expect(draft.text == "Keep my unsent message")
        #expect(!model.canGoBack)
        model.goForward()
        #expect(model.destination == .tools)
        #expect(model.nativeToolPath.isEmpty)
    }

    @Test("Deleted conversations and tools are unavailable to window history")
    func deletedNavigationDestinations() async throws {
        let suiteName = "DeletedNavigationTests-\(UUID().uuidString)"
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
        try model.conversations.append(.user("History"), to: first)
        model.newConversation()
        let second = try #require(model.selectedConversation)
        model.openNativeToolLibrary()
        await model.deleteConversation(second)
        model.goBack()
        #expect(model.destination == .conversation(first.id))
        model.goForward()
        #expect(model.destination == .tools)
        await model.nativeTools.load()
        let tool = try #require(model.nativeTools.records.first)
        model.openNativeTool(tool.id)
        model.destination = .conversation(first.id)
        try await model.nativeTools.store.delete(tool.id)
        await model.nativeTools.load()
        model.goBack()
        #expect(model.destination == .tools)
        #expect(model.nativeToolPath.isEmpty)
    }
#endif

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
            preferredModelStore: PreferredModelStore(defaults: defaults),
            nativeToolStore: NativeToolStore(
                paths: paths,
                builtInTools: try BuiltInNativeTools.load(
                    from: NativeToolTestFixtures.skillDirectory.deletingLastPathComponent()
                )
            ),
            modeDefaults: defaults
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
