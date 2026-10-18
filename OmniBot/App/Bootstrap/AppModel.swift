import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    private(set) var conversationMode: ConversationMode = .task {
        didSet { modeDefaults.set(conversationMode.rawValue, forKey: "conversationMode") }
    }
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
    var nativeToolPath: [UUID] = [] {
        didSet {
#if os(macOS)
            guard nativeToolPath != oldValue else { return }
            nativeToolScreenID = nil
            recordNavigationVisit()
#endif
        }
    }
    var destination: AppDestination? {
        didSet {
            if case let .conversation(identifier) = destination {
                lastConversationID = identifier
                if let conversation = conversations.conversation(id: identifier) {
                    conversationMode = conversation.mode
                    lastConversationIDs[conversation.mode] = identifier
                }
#if os(iOS)
                selectedTab = .conversations
                if conversationPath.last != identifier { conversationPath = [identifier] }
#endif
            }
            if destination == .tools { conversationMode = .task }
#if os(macOS)
            if destination != oldValue { modeSwitchFocusConversationID = nil }
            recordNavigationVisit()
#endif
        }
    }
#if os(macOS)
    let keyboardShortcuts = KeyboardShortcutSettingsModel()
    var sidebarSearchRequestID = 0
    var sidebarWidth = AppDesign.sidebarIdealWidth {
        didSet { modeDefaults.set(sidebarWidth, forKey: "sidebarWidth") }
    }
    private(set) var modeSwitchFocusConversationID: UUID?
    var nativeToolScreenID: String? {
        didSet { recordNavigationVisit() }
    }
    var navigationHistory = AppNavigationHistory()
    @ObservationIgnored var isRestoringNavigation = false
#endif
    var globalErrorMessage: String?
    var presentedSettingsDestination: SettingsCardDestination?
    var isTerminalPresented = false
    private(set) var hasStarted = false
    private var lastConversationID: UUID?
    @ObservationIgnored private var lastConversationIDs: [ConversationMode: UUID] = [:]
    @ObservationIgnored private let modeDefaults: UserDefaults
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var chatDrafts: [UUID: ChatComposerDraft] = [:]

    var selectedConversation: ConversationRecord? {
        if let lastConversationID,
           let conversation = conversations.conversation(id: lastConversationID),
           conversation.mode == conversationMode {
            return conversation
        }
        return modeConversations.first
    }

    var modeConversations: [ConversationRecord] {
        conversations.conversations.filter { $0.mode == conversationMode }
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
    let cloudSync: CloudSyncModel

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
        nativeToolStore: NativeToolStore? = nil,
        modeDefaults: UserDefaults = .standard
    ) {
        self.modeDefaults = modeDefaults
        self.conversationMode = modeDefaults.string(forKey: "conversationMode")
            .flatMap(ConversationMode.init(rawValue:)) ?? .task
#if os(macOS)
        self.sidebarWidth = modeDefaults.object(forKey: "sidebarWidth") as? Double ?? AppDesign.sidebarIdealWidth
#endif
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
        self.cloudSync = CloudSyncModel(conversations: conversations, providers: providerStore,
                                        preferences: preferredModelStore, paths: workspacePaths, keychain: keychain)
        cloudSync.canApplyChanges = { [weak self] in
            guard let self else { return false }
            return self.hasStarted && self.chatCoordinator.busyConversationID == nil
                && !self.chatCoordinator.sharedMemory.isUpdating
                && !self.providerSettings.isMutating && !self.skillSettings.isMutating
        }
        cloudSync.didImportChanges = { [weak self] in
            guard let self else { return }
            await self.providerSettings.refreshAfterSync()
            await self.soulSettings.load()
            await self.memorySettings.load()
            await self.skillSettings.load()
            await self.appearanceSettings.load()
            self.conversationPath.removeAll { self.conversations.conversation(id: $0) == nil }
            if let id = self.lastConversationID, self.conversations.conversation(id: id) == nil {
                self.lastConversationID = nil
                self.destination = nil
            }
        }
        chatCoordinator.onWorkFinished = { [weak cloudSync] in cloudSync?.requestSync() }
        chatCoordinator.sharedMemory.onWorkFinished = { [weak cloudSync] in cloudSync?.requestSync() }
        chatCoordinator.sharedMemory.onMemoryUpdated = { [weak memorySettings] in
            await memorySettings?.load()
        }
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
            cloudSync.start()

#if os(macOS)
            if modeConversations.isEmpty {
                newConversation()
            } else if destination == nil, let first = modeConversations.first {
                destination = .conversation(first.id)
            }
#endif

            // Alpine prepares lazily when a task actually uses it. A chat must
            // remain usable even when the task runtime is unavailable.
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
            if let draftConversation = modeConversations.first(where: {
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
                modelID: selection?.modelID ?? "",
                mode: conversationMode
            )
            destination = .conversation(conversation.id)
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func selectConversationMode(_ mode: ConversationMode) {
        guard mode != conversationMode else { return }
        conversationMode = mode
        selectedTab = .conversations
        isTerminalPresented = false
        let remembered = lastConversationIDs[mode].flatMap { conversations.conversation(id: $0) }
        let conversation = remembered?.mode == mode ? remembered : modeConversations.first
        lastConversationID = conversation?.id
#if os(iOS)
        conversationPath = []
        destination = nil
#else
        if let conversation {
            destination = .conversation(conversation.id)
        } else {
            newConversation()
        }
        if case let .conversation(id) = destination,
           conversations.conversation(id: id)?.mode == mode {
            modeSwitchFocusConversationID = id
        }
#endif
    }

#if os(macOS)
    func consumeModeSwitchComposerFocus(for conversationID: UUID) -> Bool {
        guard modeSwitchFocusConversationID == conversationID,
              destination == .conversation(conversationID) else { return false }
        modeSwitchFocusConversationID = nil
        return true
    }
#endif

    func openNativeTool(_ id: UUID) {
        conversationMode = .task
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
            throw NativeToolError(String(localized: "请先在 Skills 中启用「原生工具制作」。"))
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
            globalErrorMessage = String(localized: "正在准备编辑或重试，暂时无法删除这个会话。")
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
            if destination == .conversation(conversation.id) {
                if let first = modeConversations.first {
                    destination = .conversation(first.id)
                } else {
                    newConversation()
                }
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
        guard conversationMode == .task else { return }
        isTerminalPresented = true
    }

    func dismissTerminal() {
        isTerminalPresented = false
    }
}
