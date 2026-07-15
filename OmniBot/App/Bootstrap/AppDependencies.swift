import Foundation
import SwiftData

enum AppBootstrapError: LocalizedError {
    case missingAlpineRootFileSystem

    var errorDescription: String? {
        switch self {
        case .missingAlpineRootFileSystem:
            "应用包中缺少 Alpine 根文件系统。"
        }
    }
}

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let appModel: AppModel

    static func live(bundle: Bundle = .main) throws -> AppDependencies {
        let schema = Schema([
            ConversationRecord.self,
            MessageRecord.self,
        ])
        let configuration = ModelConfiguration(
            "OmniBotAgent",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        let modelContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )

        let workspacePaths = try WorkspacePaths.applicationSupport()
        try workspacePaths.prepare()

        guard let rootFileSystemArchiveURL = bundle.url(
            forResource: "alpine-minirootfs-3.21.0-aarch64",
            withExtension: "tar.gz"
        ) else {
            throw AppBootstrapError.missingAlpineRootFileSystem
        }

        let soulStore = SoulStore(paths: workspacePaths)
        let memoryStore = MarkdownMemoryStore(paths: workspacePaths)
        let skillStore = AgentSkillStore(paths: workspacePaths)
        let appearanceStore = AppearanceSettingsStore(
            directoryURL: workspacePaths.hostOmniBotDirectory.appending(
                path: "appearance",
                directoryHint: .isDirectory
            )
        )
        let providerBootstrap = try recoverProviderStoreIfNeeded(
            fileURL: workspacePaths.providerConfigFile
        )
        let providerStore = providerBootstrap.store
        let keychain = KeychainAPIKeyStore()
        let alpineRootFileSystemStateDirectory = workspacePaths.root
            .deletingLastPathComponent()
            .appending(path: "AlpineRoot", directoryHint: .isDirectory)
        let alpineRootFileSystemResetRequestURL = workspacePaths.hostOmniBotDirectory
            .appending(path: "alpine-rootfs-reset-requested", directoryHint: .notDirectory)
        try AlpineRootFileSystemStorage.applyScheduledResetIfNeeded(
            stateDirectory: alpineRootFileSystemStateDirectory,
            resetRequestURL: alpineRootFileSystemResetRequestURL
        )
        let alpineRootFileSystem = AlpineRootFileSystemManager(
            stateDirectory: alpineRootFileSystemStateDirectory,
            resetRequestURL: alpineRootFileSystemResetRequestURL
        )
        let alpineRuntime = AlpineRuntime(
            rootFileSystemArchiveURL: rootFileSystemArchiveURL,
            stateDirectory: alpineRootFileSystemStateDirectory,
            workspaceDirectory: workspacePaths.root
        )
        let toolActivity = ChatToolActivityModel()
        let fileManager = FileManager.default
        let appleAlarmService: AppleAlarmService?
#if os(iOS)
        appleAlarmService = AppleAlarmService(
            recordFileURL: workspacePaths.agentDirectory.appending(
                path: "alarms.json",
                directoryHint: .notDirectory
            )
        )
#else
        appleAlarmService = nil
#endif
        let agentPermissionStore = AgentPermissionStore()
        let browserSession = AppleBrowserSession(
            paths: workspacePaths,
            fileManager: fileManager,
            websiteDataStorePolicy: .nonPersistentPerConversation
        )
        let toolExecutor = OmniAgentToolExecutor(
            paths: workspacePaths,
            memoryStore: memoryStore,
            skillStore: skillStore,
            commandRunner: OmniTerminalCommandRunner(alpineRuntime: alpineRuntime),
            terminalOutputHandler: { runID, callID, line, isStandardError in
                toolActivity.appendTerminalOutput(
                    line,
                    isStandardError: isStandardError,
                    runID: runID,
                    callID: callID
                )
            },
            agentPermissionStore: agentPermissionStore,
            appleAlarmService: appleAlarmService,
            appleCalendarService: AppleCalendarService(),
            appleContactsService: AppleContactsService(),
            appleHealthKitService: AppleHealthKitService(),
            browserSession: browserSession
        )
        let appModel = AppModel(
            modelContext: modelContainer.mainContext,
            workspacePaths: workspacePaths,
            providerStore: providerStore,
            keychain: keychain,
            alpineRuntime: alpineRuntime,
            alpineRootFileSystem: alpineRootFileSystem,
            toolActivity: toolActivity,
            toolExecutor: toolExecutor,
            browserSession: browserSession,
            soulStore: soulStore,
            memoryStore: memoryStore,
            skillStore: skillStore,
            appearanceStore: appearanceStore,
            bootstrapNotice: providerBootstrap.notice
        )

        return AppDependencies(
            modelContainer: modelContainer,
            appModel: appModel
        )
    }

    /// Unsafe/corrupt provider metadata is host control data, not user
    /// workspace content. Preserve it for diagnosis, then start with an empty
    /// profile store. Keychain endpoint binding prevents any orphan key from
    /// being attached to the replacement configuration.
    static func recoverProviderStoreIfNeeded(
        fileURL: URL,
        fileManager: FileManager = .default
    ) throws -> (store: ProviderStore, notice: String?, quarantineURL: URL?) {
        do {
            return (try ProviderStore(fileURL: fileURL), nil, nil)
        } catch {
            guard fileManager.fileExists(atPath: fileURL.path) else { throw error }
            let quarantineURL = fileURL
                .deletingLastPathComponent()
                .appending(
                    path: "providers.invalid-\(UUID().uuidString).json",
                    directoryHint: .notDirectory
                )
            try fileManager.moveItem(at: fileURL, to: quarantineURL)
            do {
                let store = try ProviderStore(fileURL: fileURL)
                let notice = "模型服务配置无法安全读取，已隔离为 \(quarantineURL.lastPathComponent)。请重新配置服务商和 API Key；旧钥匙串凭据不会自动复用。"
                return (store, notice, quarantineURL)
            } catch {
                // Best effort rollback retains the original evidence if even
                // constructing an empty store unexpectedly fails.
                try? fileManager.moveItem(at: quarantineURL, to: fileURL)
                throw error
            }
        }
    }
}
