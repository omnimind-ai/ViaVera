import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    var destination: AppDestination? {
        didSet {
            if case let .conversation(identifier) = destination {
                lastConversationID = identifier
            }
        }
    }
    var globalErrorMessage: String?
    var presentedSettingsDestination: SettingsCardDestination?
    var isTerminalPresented = false
    private(set) var hasStarted = false
    private var lastConversationID: UUID?
    @ObservationIgnored private var startupTask: Task<Void, Never>?

    var selectedConversation: ConversationRecord? {
        if let lastConversationID,
           let conversation = conversations.conversation(id: lastConversationID) {
            return conversation
        }
        return conversations.conversations.first
    }

    private let bootstrapNotice: String?

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
        bootstrapNotice: String? = nil
    ) {
        self.bootstrapNotice = bootstrapNotice
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
            await appearanceSettings.load()

            if conversations.conversations.isEmpty {
                newConversation()
            } else if destination == nil, let first = conversations.conversations.first {
                destination = .conversation(first.id)
            }

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
        if let draftConversation = conversations.draftConversation {
            destination = .conversation(draftConversation.id)
            return
        }

        do {
            let profile = providerSettings.profiles.first { profile in
                profile.isEnabled && profile.models.contains { !$0.isHidden }
            }
            let conversation = try conversations.createConversation(
                providerID: profile?.id,
                modelID: profile?.models.first(where: { !$0.isHidden })?.id ?? ""
            )
            destination = .conversation(conversation.id)
        } catch {
            globalErrorMessage = error.localizedDescription
        }
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
            if conversations.conversations.isEmpty {
                newConversation()
            } else if destination == .conversation(conversation.id),
                      let first = conversations.conversations.first {
                destination = .conversation(first.id)
            }
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
