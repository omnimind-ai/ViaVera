import Foundation

public actor OmniAgentToolExecutor: AgentToolExecuting {
    private struct ToolCancellationKey: Hashable {
        let runID: UUID
        let callID: String
    }

    public typealias TerminalOutputHandler = @MainActor @Sendable (
        _ runID: UUID,
        _ callID: String,
        _ line: String,
        _ isStandardError: Bool
    ) -> Void

    let paths: WorkspacePaths
    let memoryStore: MarkdownMemoryStore
    let skillStore: AgentSkillStore
    let resourceProtocol: AgentResourceProtocol
    let commandRunner: OmniTerminalCommandRunner
    let limits: OmniAgentToolLimits
    let descriptorFileSystem: WorkspaceDescriptorFileSystem
    let fileManager: FileManager
    let terminalOutputHandler: TerminalOutputHandler?
    let agentPermissionStore: AgentPermissionStore?
    let appleAlarmService: AppleAlarmService?
    let appleCalendarService: AppleCalendarService?
    let appleContactsService: AppleContactsService?
    let appleHealthKitService: AppleHealthKitService?
    let browserSession: AppleBrowserSession?

    var terminalSessions: [UUID: OmniTerminalSession] = [:]
    var activeTerminalCommands: [UUID: OmniActiveTerminalCommand] = [:]
    private var activeToolCallIDsByRun: [UUID: String] = [:]
    private var userCancelledTools: Set<ToolCancellationKey> = []

    public init(
        paths: WorkspacePaths,
        memoryStore: MarkdownMemoryStore,
        skillStore: AgentSkillStore? = nil,
        commandRunner: OmniTerminalCommandRunner,
        limits: OmniAgentToolLimits = .default,
        terminalOutputHandler: TerminalOutputHandler? = nil
    ) {
        self.init(
            paths: paths,
            memoryStore: memoryStore,
            skillStore: skillStore,
            commandRunner: commandRunner,
            limits: limits,
            terminalOutputHandler: terminalOutputHandler,
            agentPermissionStore: nil,
            appleAlarmService: nil,
            appleCalendarService: nil,
            appleContactsService: nil,
            appleHealthKitService: nil,
            browserSession: nil
        )
    }

    init(
        paths: WorkspacePaths,
        memoryStore: MarkdownMemoryStore,
        skillStore: AgentSkillStore? = nil,
        commandRunner: OmniTerminalCommandRunner,
        limits: OmniAgentToolLimits = .default,
        terminalOutputHandler: TerminalOutputHandler? = nil,
        agentPermissionStore: AgentPermissionStore?,
        appleAlarmService: AppleAlarmService?,
        appleCalendarService: AppleCalendarService?,
        appleContactsService: AppleContactsService?,
        appleHealthKitService: AppleHealthKitService?,
        browserSession: AppleBrowserSession?
    ) {
        self.paths = paths
        self.memoryStore = memoryStore
        self.skillStore = skillStore ?? AgentSkillStore(paths: paths)
        resourceProtocol = AgentResourceProtocol(paths: paths)
        self.commandRunner = commandRunner
        self.limits = limits
        self.terminalOutputHandler = terminalOutputHandler
        self.agentPermissionStore = agentPermissionStore
        descriptorFileSystem = WorkspaceDescriptorFileSystem(paths: paths)
        self.fileManager = .default
        self.appleAlarmService = appleAlarmService
        self.appleCalendarService = appleCalendarService
        self.appleContactsService = appleContactsService
        self.appleHealthKitService = appleHealthKitService
        self.browserSession = browserSession
    }

    public nonisolated func availableTools() async -> [AgentToolDefinition] {
        OmniAgentToolDefinitions.all
    }

    public func execute(
        _ call: AgentToolCall,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        let cancellationKey = ToolCancellationKey(runID: context.runID, callID: call.id)
        activeToolCallIDsByRun[context.runID] = call.id
        defer {
            if activeToolCallIDsByRun[context.runID] == call.id {
                activeToolCallIDsByRun[context.runID] = nil
            }
        }

        do {
            try Task.checkCancellation()
            try validate(context: context)
            try await validateAgentPermission(for: call.name)
            try paths.prepare(fileManager: fileManager)
            let arguments = try OmniToolArguments(call: call)

            let result: AgentToolExecutionResult
            switch call.name {
            case "terminal_execute":
                result = try await executeTerminal(
                    arguments,
                    callID: call.id,
                    context: context
                )
            case "terminal_session_start":
                result = try startTerminalSession(arguments, context: context)
            case "terminal_session_exec":
                result = try await executeInTerminalSession(
                    arguments,
                    callID: call.id,
                    context: context
                )
            case "terminal_session_read":
                result = try readTerminalSession(arguments, context: context)
            case "terminal_session_stop":
                result = try stopTerminalSession(arguments, context: context)
            case "file_read":
                result = try readFile(arguments)
            case "file_write":
                result = try writeFile(arguments)
            case "file_edit":
                result = try editFile(arguments)
            case "file_list":
                result = try listFiles(arguments)
            case "file_search":
                result = try searchFiles(arguments)
            case "file_stat":
                result = try statFile(arguments)
            case "file_move":
                result = try moveFile(arguments)
            case "memory_search":
                result = try await searchMemory(arguments)
            case "memory_load":
                result = try await loadMemory(arguments)
            case "memory_write_daily":
                result = try await writeDailyMemory(arguments)
            case "memory_upsert_longterm":
                result = try await upsertLongTermMemory(arguments)
            case "skills_list":
                result = try await listSkills(arguments)
            case "skills_read":
                result = try await readSkill(arguments)
            case "browser_use":
                result = try await executeBrowser(arguments, context: context)
            case "healthkit_data_types":
                result = try await requiredHealthKitService().listDataTypes(arguments)
            case "healthkit_request_access":
                result = try await requiredHealthKitService().requestAccess(arguments)
            case "healthkit_quantity_samples":
                result = try await requiredHealthKitService().quantitySamples(arguments)
            case "healthkit_quantity_statistics":
                result = try await requiredHealthKitService().quantityStatistics(arguments)
            case "healthkit_category_samples":
                result = try await requiredHealthKitService().categorySamples(arguments)
            case "healthkit_workout_list":
                result = try await requiredHealthKitService().listWorkouts(arguments)
            case "alarm_reminder_create":
                result = try await requiredAlarmService().create(arguments)
            case "alarm_reminder_list":
                result = try await requiredAlarmService().list(arguments)
            case "alarm_reminder_delete":
                result = try await requiredAlarmService().delete(arguments)
            case "calendar_list":
                result = try await requiredCalendarService().listCalendars(arguments)
            case "calendar_event_create":
                result = try await requiredCalendarService().createEvent(arguments)
            case "calendar_event_list":
                result = try await requiredCalendarService().listEvents(arguments)
            case "calendar_event_update":
                result = try await requiredCalendarService().updateEvent(arguments)
            case "calendar_event_delete":
                result = try await requiredCalendarService().deleteEvent(arguments)
            case "contacts_search":
                result = try await requiredContactsService().search(arguments)
            case "contacts_create":
                result = try await requiredContactsService().create(arguments)
            case "contacts_update":
                result = try await requiredContactsService().update(arguments)
            case "contacts_delete":
                result = try await requiredContactsService().delete(arguments)
            default:
                throw OmniAgentToolError("Unknown tool: \(call.name).")
            }

            return addingToolContext(
                name: call.name,
                title: arguments.toolTitle,
                conversationID: context.conversationID,
                to: result
            )
        } catch is CancellationError where userCancelledTools.remove(cancellationKey) != nil {
            return AgentToolExecutionResult(
                content: "用户已停止当前工具调用。",
                isError: true,
                metadata: Self.baseToolMetadata(name: call.name).merging([
                    "interrupted": .bool(true),
                    "status": .string("interrupted"),
                ]) { _, new in new }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ApplePersonalToolError {
            let metadata = Self.baseToolMetadata(name: call.name)
                .merging(error.metadata) { _, new in new }
            return AgentToolExecutionResult(
                content: error.localizedDescription,
                isError: true,
                metadata: metadata,
                actions: error.actions
            )
        } catch {
            return AgentToolExecutionResult(
                content: error.localizedDescription,
                isError: true,
                metadata: Self.baseToolMetadata(name: call.name)
            )
        }
    }

    public func cancel(runID: UUID) async {
        userCancelledTools = Set(userCancelledTools.filter { $0.runID != runID })
        for command in activeTerminalCommands.values where command.runID == runID {
            command.task.cancel()
        }
    }

    public func cancelCurrentTool(runID: UUID, callID: String) async -> Bool {
        guard activeToolCallIDsByRun[runID] == callID else { return false }
        userCancelledTools.insert(ToolCancellationKey(runID: runID, callID: callID))
        let commands = activeTerminalCommands.values.filter {
            $0.runID == runID && $0.callID == callID
        }
        for command in commands {
            command.task.cancel()
        }
        return true
    }

    func checkForUserToolCancellation(runID: UUID, callID: String) throws {
        if userCancelledTools.contains(ToolCancellationKey(runID: runID, callID: callID)) {
            throw CancellationError()
        }
    }

    private func validate(context: AgentToolExecutionContext) throws {
        let expected = paths.root.resolvingSymlinksInPath().standardizedFileURL
        let supplied = context.workspaceURL.resolvingSymlinksInPath().standardizedFileURL
        guard supplied == expected else {
            throw OmniAgentToolError(
                "Tool execution workspace does not match the executor workspace."
            )
        }
    }

    private func validateAgentPermission(for toolName: String) async throws {
        guard let permission = IOSPermissionKind.requiredPermission(
            forAgentToolName: toolName
        ), let agentPermissionStore else {
            return
        }
        guard await agentPermissionStore.isEnabled(permission) else {
            throw ApplePersonalToolError(
                "已在 Via Vera 设置中关闭\(permission.title)权限，Agent 无法调用此工具。",
                code: "permission_disabled_in_app",
                permission: permission.rawValue,
                authorizationStatus: "disabled_in_app",
                backend: "via_vera_permissions",
                requiresUserInteraction: true,
                guidance: "请先在 Via Vera 的“设置 > 系统 > 权限”中打开\(permission.title)开关。"
            )
        }
    }

    private func addingToolContext(
        name: String,
        title: String,
        conversationID: UUID,
        to result: AgentToolExecutionResult
    ) -> AgentToolExecutionResult {
        var metadata = result.metadata
        metadata["toolTitle"] = .string(title)
        metadata["toolName"] = .string(name)
        metadata["displayName"] = .string(name)
        metadata["toolType"] = .string(Self.toolType(for: name))
        return AgentToolExecutionResult(
            content: result.content,
            isError: result.isError,
            metadata: metadata,
            artifacts: result.artifacts,
            workspaceID: result.workspaceID == nil
                ? nil
                : conversationID.uuidString,
            actions: result.actions
        )
    }

    private nonisolated static func toolType(for name: String) -> String {
        if name.hasPrefix("terminal_") { return "terminal" }
        if name.hasPrefix("file_") { return "filesystem" }
        if name.hasPrefix("memory_") { return "memory" }
        if name.hasPrefix("skills_") { return "skills" }
        if name == "browser_use" { return "browser" }
        if name.hasPrefix("healthkit_") { return "healthkit" }
        if name.hasPrefix("alarm_") { return "alarm" }
        if name.hasPrefix("calendar_") { return "calendar" }
        if name.hasPrefix("contacts_") { return "contacts" }
        return "builtin"
    }

    private nonisolated static func baseToolMetadata(
        name: String
    ) -> [String: AgentValue] {
        [
            "tool": .string(name),
            "toolName": .string(name),
            "displayName": .string(name),
            "toolType": .string(toolType(for: name)),
        ]
    }

    private func requiredAlarmService() throws -> AppleAlarmService {
        guard let appleAlarmService else {
            throw ApplePersonalToolError(
                "Apple alarm tools are unavailable in this executor configuration.",
                code: "service_unavailable",
                backend: "apple_platform"
            )
        }
        return appleAlarmService
    }

    private func requiredCalendarService() throws -> AppleCalendarService {
        guard let appleCalendarService else {
            throw ApplePersonalToolError(
                "Apple calendar tools are unavailable in this executor configuration.",
                code: "service_unavailable",
                backend: "eventkit"
            )
        }
        return appleCalendarService
    }

    private func requiredContactsService() throws -> AppleContactsService {
        guard let appleContactsService else {
            throw ApplePersonalToolError(
                "Apple contacts tools are unavailable in this executor configuration.",
                code: "service_unavailable",
                backend: "contacts"
            )
        }
        return appleContactsService
    }

    private func requiredHealthKitService() throws -> AppleHealthKitService {
        guard let appleHealthKitService else {
            throw ApplePersonalToolError(
                "HealthKit tools are unavailable in this executor configuration.",
                code: "service_unavailable",
                permission: "healthkit",
                backend: "healthkit"
            )
        }
        return appleHealthKitService
    }
}
