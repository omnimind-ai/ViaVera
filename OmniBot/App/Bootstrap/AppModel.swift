import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .conversations
    var conversationPath: [UUID] = [] {
        didSet {
            if let id = conversationPath.last { lastConversationID = id }
#if os(iOS)
            let selected = conversationPath.last.map(AppDestination.conversation)
            if destination != selected { destination = selected }
#endif
        }
    }
    var nativeToolPath: [UUID] = []
    var destination: AppDestination? {
        didSet {
            if case let .conversation(identifier) = destination {
                lastConversationID = identifier
#if os(iOS)
                selectedTab = .conversations
                if conversationPath.last != identifier { conversationPath = [identifier] }
#endif
            }
        }
    }
    var globalErrorMessage: String?
    var presentedSettingsDestination: SettingsCardDestination?
    var isTerminalPresented = false
    private(set) var hasStarted = false
    private var lastConversationID: UUID?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var chatDrafts: [UUID: ChatComposerDraft] = [:]

    var selectedConversation: ConversationRecord? {
        if let lastConversationID,
           let conversation = conversations.conversation(id: lastConversationID) {
            return conversation
        }
        return conversations.conversations.first
    }

    private let bootstrapNotice: String?
    private let preferredModelStore: PreferredModelStore

    let workspacePaths: WorkspacePaths
    let attachmentImporter: WorkspaceAttachmentImporter
    var resourceProtocol: AgentResourceProtocol {
        AgentResourceProtocol(paths: workspacePaths)
    }
    let conversations: ConversationRepository
    let providerSettings: ProviderSettingsModel
    let soulSettings: SoulSettingsModel
    let memorySettings: MemorySettingsModel
    let skillSettings: SkillSettingsModel
    let nativeTools: NativeToolLibraryModel
    let appearanceSettings: AppearanceSettingsModel
    let workspaceBrowser: WorkspaceBrowserModel
    let alpineRuntime: AlpineRuntime
    let alpineRootFileSystem: AlpineRootFileSystemManager
    let alpineEnvironmentSettings: AlpineEnvironmentSettingsModel
    let interactiveTerminal: InteractiveTerminalModel
    let toolActivity: ChatToolActivityModel
    let browserSession: AppleBrowserSession
    let chatCoordinator: ChatCoordinator

    init(
        modelContext: ModelContext,
        workspacePaths: WorkspacePaths,
        providerStore: ProviderStore,
        keychain: any APIKeyStoring,
        alpineRuntime: AlpineRuntime,
        alpineRootFileSystem: AlpineRootFileSystemManager,
        toolActivity: ChatToolActivityModel,
        toolExecutor: any AgentToolExecuting,
        browserSession: AppleBrowserSession,
        soulStore: SoulStore,
        memoryStore: MarkdownMemoryStore,
        skillStore: AgentSkillStore,
        appearanceStore: AppearanceSettingsStore,
        bootstrapNotice: String? = nil,
        preferredModelStore: PreferredModelStore = PreferredModelStore(),
        nativeToolStore: NativeToolStore? = nil
    ) {
        self.bootstrapNotice = bootstrapNotice
        self.preferredModelStore = preferredModelStore
        self.workspacePaths = workspacePaths
        self.attachmentImporter = WorkspaceAttachmentImporter(paths: workspacePaths)
        self.alpineRuntime = alpineRuntime
        self.alpineRootFileSystem = alpineRootFileSystem
        self.toolActivity = toolActivity
        self.browserSession = browserSession

        let conversations = ConversationRepository(modelContext: modelContext)
        let providerSettings = ProviderSettingsModel(store: providerStore, keychain: keychain)
        let soulSettings = SoulSettingsModel(store: soulStore)
        let memorySettings = MemorySettingsModel(store: memoryStore)
        let skillSettings = SkillSettingsModel(store: skillStore)
        let appearanceSettings = AppearanceSettingsModel(store: appearanceStore)

        self.conversations = conversations
        self.providerSettings = providerSettings
        self.soulSettings = soulSettings
        self.memorySettings = memorySettings
        self.skillSettings = skillSettings
        self.nativeTools = NativeToolLibraryModel(store: nativeToolStore ?? NativeToolStore(paths: workspacePaths))
        self.appearanceSettings = appearanceSettings
        self.workspaceBrowser = WorkspaceBrowserModel(paths: workspacePaths)
        self.alpineEnvironmentSettings = AlpineEnvironmentSettingsModel(commandRunner: alpineRuntime)
        self.interactiveTerminal = InteractiveTerminalModel(runtime: alpineRuntime)
        self.chatCoordinator = ChatCoordinator(
            conversations: conversations,
            providerSettings: providerSettings,
            soulStore: soulStore,
            memoryStore: memoryStore,
            skillStore: skillStore,
            toolExecutor: toolExecutor,
            toolActivity: toolActivity,
            workspacePaths: workspacePaths
        )
    }

    func start() async {
        if let startupTask {
            await startupTask.value
            return
        }
        guard !hasStarted else { return }
        // Startup belongs to the application, so dismissing a menu bar window
        // must not cancel it or trigger a second load from another scene.
        let task = Task { await loadInitialState() }
        startupTask = task
        await task.value
        startupTask = nil
    }

    private func loadInitialState() async {
        hasStarted = true
        globalErrorMessage = nil
        do {
            try workspacePaths.prepare()
            try conversations.reload()
            try conversations.recoverInterruptedRuns()
            await providerSettings.load()
            await soulSettings.load()
            await memorySettings.load()
            await skillSettings.load()
            await nativeTools.load()
            await appearanceSettings.load()

#if os(macOS)
            if conversations.conversations.isEmpty {
                newConversation()
            } else if destination == nil, let first = conversations.conversations.first {
                destination = .conversation(first.id)
            }
#endif

            try await alpineRuntime.prepare()
            if let bootstrapNotice {
                globalErrorMessage = bootstrapNotice
            }
        } catch {
            hasStarted = false
            globalErrorMessage = error.localizedDescription
        }
    }

    func newConversation() {
        do {
            let selection = preferredModelStore.selection(in: providerSettings.profiles)
            if let draftConversation = conversations.conversations.first(where: {
                $0.status == .idle && $0.messages.isEmpty && chatDrafts[$0.id]?.skillReference == nil
            }) {
                if draftConversation.providerID != selection?.providerID
                    || draftConversation.modelID != (selection?.modelID ?? "") {
                    try conversations.updateModel(
                        providerID: selection?.providerID,
                        modelID: selection?.modelID ?? "",
                        for: draftConversation
                    )
                }
                destination = .conversation(draftConversation.id)
                return
            }

            let conversation = try conversations.createConversation(
                providerID: selection?.providerID,
                modelID: selection?.modelID ?? ""
            )
            destination = .conversation(conversation.id)
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func openNativeTool(_ id: UUID) {
        selectedTab = .tools
        nativeToolPath = [id]
#if os(macOS)
        destination = .tools
#endif
    }

    func chatDraft(for conversationID: UUID) -> ChatComposerDraft {
        if let existing = chatDrafts[conversationID] { return existing }
        let draft = ChatComposerDraft()
        chatDrafts[conversationID] = draft
        return draft
    }

    func beginNativeToolConversation(editing id: UUID? = nil) throws {
        guard skillSettings.skills.contains(where: { $0.id == "native-tool-builder" && $0.enabled }) else {
            throw NativeToolError("请先在 Skills 中启用「原生工具制作」。")
        }
        let selection = preferredModelStore.selection(in: providerSettings.profiles)
        let conversation = try conversations.createConversation(providerID: selection?.providerID, modelID: selection?.modelID ?? "")
        let draft = chatDraft(for: conversation.id)
        draft.skillReference = .nativeToolBuilder(editing: id)
        draft.requestsFocus = true
        destination = .conversation(conversation.id)
    }

    func deleteConversation(_ conversation: ConversationRecord) async {
        if chatCoordinator.pendingResendConversationID == conversation.id {
            globalErrorMessage = "正在准备编辑或重试，暂时无法删除这个会话。"
            return
        }
        if chatCoordinator.isRunning(conversation) {
            await chatCoordinator.cancel()
        }
        do {
            try conversations.delete(conversation)
            chatDrafts.removeValue(forKey: conversation.id)
#if os(iOS)
            conversationPath.removeAll { $0 == conversation.id }
            if lastConversationID == conversation.id { lastConversationID = nil }
#else
            if conversations.conversations.isEmpty {
                newConversation()
            } else if destination == .conversation(conversation.id),
                      let first = conversations.conversations.first {
                destination = .conversation(first.id)
            }
#endif
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func selectModel(providerID: String, modelID: String, for conversation: ConversationRecord) {
        do {
            try conversations.updateModel(
                providerID: providerID,
                modelID: modelID,
                for: conversation
            )
            preferredModelStore.remember(
                ProviderModelSelection(providerID: providerID, modelID: modelID)
            )
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func selectReasoningEffort(
        _ effort: AgentReasoningEffort,
        for conversation: ConversationRecord
    ) {
        do {
            try conversations.updateReasoningEffort(effort, for: conversation)
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func toggleConversationPinned(_ conversation: ConversationRecord) {
        do {
            try conversations.setPinned(!conversation.isPinned, for: conversation)
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func renameConversation(_ conversation: ConversationRecord, to title: String) {
        do {
            try conversations.rename(conversation, to: title)
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func presentSettings(_ destination: SettingsCardDestination = .providers) {
        presentedSettingsDestination = destination
    }

    func dismissSettings() {
        presentedSettingsDestination = nil
    }

    func presentTerminal() {
        isTerminalPresented = true
    }

    func dismissTerminal() {
        isTerminalPresented = false
    }
}
