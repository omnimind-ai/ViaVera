import Foundation
import Observation

@MainActor
@Observable
final class ChatCoordinator {
    private(set) var runningConversationID: UUID?
    private(set) var pendingResendConversationID: UUID?
    private(set) var compactingConversationID: UUID?
    private(set) var statusMessage: String?
    private(set) var latestUsage = AgentUsage.zero
    private(set) var lastCompactionConversationID: UUID?
    private(set) var lastCompactionMessage: String?
    private(set) var lastCompactionFailed = false
    var errorMessage: String?

    private let conversations: ConversationRepository
    private let providerSettings: ProviderSettingsModel
    private let soulStore: SoulStore
    private let memoryStore: MarkdownMemoryStore
    private let skillStore: AgentSkillStore
    private let toolExecutor: any AgentToolExecuting
    private let toolActivity: ChatToolActivityModel
    private let workspacePaths: WorkspacePaths
    private let promptBuilder = AgentSystemPromptBuilder()

    private var runTask: Task<Void, Never>?
    private var currentRunner: AgentRunner?
    private var currentRunID: UUID?
    private var isResendInProgress = false

    init(
        conversations: ConversationRepository,
        providerSettings: ProviderSettingsModel,
        soulStore: SoulStore,
        memoryStore: MarkdownMemoryStore,
        skillStore: AgentSkillStore,
        toolExecutor: any AgentToolExecuting,
        toolActivity: ChatToolActivityModel,
        workspacePaths: WorkspacePaths
    ) {
        self.conversations = conversations
        self.providerSettings = providerSettings
        self.soulStore = soulStore
        self.memoryStore = memoryStore
        self.skillStore = skillStore
        self.toolExecutor = toolExecutor
        self.toolActivity = toolActivity
        self.workspacePaths = workspacePaths
    }

    func isRunning(_ conversation: ConversationRecord) -> Bool {
        runningConversationID == conversation.id
    }

    func isBusy(_ conversation: ConversationRecord) -> Bool {
        busyConversationID == conversation.id
    }

    var busyConversationID: UUID? {
        runningConversationID ?? pendingResendConversationID ?? compactingConversationID
    }

    func isCompacting(_ conversation: ConversationRecord) -> Bool {
        compactingConversationID == conversation.id
    }

    func send(_ text: String, in conversation: ConversationRecord) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, busyConversationID == nil else { return }
        let userMessage = AgentMessage.user(trimmed)
        runningConversationID = conversation.id
        statusMessage = "正在准备上下文…"
        runTask = Task { [weak self, weak conversation] in
            guard let self, let conversation else { return }
            await self.performRun(
                currentUserMessage: userMessage,
                conversation: conversation,
                appendUserMessage: true,
                continueMode: false
            )
        }
    }

    func retry(_ conversation: ConversationRecord) {
        guard busyConversationID == nil else { return }
        do {
            guard let currentUserMessage = try conversations.transcript(for: conversation)
                .last(where: { $0.role == .user }) else {
                throw ChatCoordinatorError.missingRetryMessage
            }
            runningConversationID = conversation.id
            statusMessage = "正在准备上下文…"
            runTask = Task { [weak self, weak conversation] in
                guard let self, let conversation else { return }
                await self.performRun(
                    currentUserMessage: currentUserMessage,
                    conversation: conversation,
                    appendUserMessage: false,
                    continueMode: true
                )
            }
        } catch {
            let description = error.localizedDescription
            errorMessage = description
            statusMessage = "无法重试"
            do {
                try conversations.updateRunOutcome(
                    status: .failed,
                    errorMessage: description,
                    usage: conversation.usage,
                    for: conversation
                )
            } catch {
                errorMessage = "\(description)\n无法保存失败状态：\(error.localizedDescription)"
            }
        }
    }

    func resendLatestUserMessage(
        _ message: MessageRecord,
        replacingWith replacementText: String?,
        in conversation: ConversationRecord
    ) async throws {
        guard !isResendInProgress else {
            throw ChatCoordinatorError.retryAlreadyInProgress
        }
        isResendInProgress = true
        defer { isResendInProgress = false }

        let conversationID = conversation.id
        let messageID = message.id
        let originalText = message.content

        if let busyConversationID, busyConversationID != conversationID {
            throw ChatCoordinatorError.anotherConversationIsRunning
        }

        pendingResendConversationID = conversationID
        var didStartRun = false
        defer {
            if pendingResendConversationID == conversationID {
                pendingResendConversationID = nil
            }
            if !didStartRun {
                runningConversationID = nil
            }
        }

        if runningConversationID == conversationID {
            await cancel()
        }

        let text = replacementText ?? originalText ?? ""
        statusMessage = "正在检查模型配置…"
        errorMessage = nil

        do {
            guard let currentConversation = conversations.conversation(id: conversationID) else {
                throw ChatCoordinatorError.conversationNotFound(conversationID)
            }
            // Editing/retrying deletes the old assistant/tool tail. Resolve all
            // fallible model credentials first so a configuration error cannot
            // destroy a still-valid previous response.
            let configuration = try await providerSettings.runtimeConfiguration(
                providerID: currentConversation.providerID,
                modelID: currentConversation.modelID
            )
            try Task.checkCancellation()
            runningConversationID = conversationID
            let userMessage = try conversations.replaceLatestUserTurn(
                messageID: messageID,
                with: text,
                in: currentConversation
            )
            guard let refreshedConversation = conversations.conversation(id: conversationID) else {
                throw ChatCoordinatorError.conversationNotFound(conversationID)
            }

            runningConversationID = refreshedConversation.id
            statusMessage = "正在准备上下文…"
            errorMessage = nil
            runTask = Task { [weak self, weak refreshedConversation] in
                guard let self, let refreshedConversation else { return }
                await self.performRun(
                    currentUserMessage: userMessage,
                    conversation: refreshedConversation,
                    appendUserMessage: false,
                    continueMode: true,
                    preparedConfiguration: configuration
                )
            }
            didStartRun = true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "无法重试"
            throw error
        }
    }

    func cancel() async {
        let task = runTask
        task?.cancel()
        if let currentRunner, let currentRunID {
            await currentRunner.cancel(runID: currentRunID)
        }
        await task?.value
    }

    func compactContext(in conversation: ConversationRecord) async {
        guard busyConversationID == nil else { return }
        let conversationID = conversation.id
        compactingConversationID = conversationID
        lastCompactionConversationID = conversationID
        lastCompactionMessage = nil
        lastCompactionFailed = false
        statusMessage = "正在压缩上下文…"
        errorMessage = nil
        defer {
            if compactingConversationID == conversationID {
                compactingConversationID = nil
            }
        }

        do {
            guard let candidate = try conversations.contextCompactionCandidate(
                for: conversation
            ) else {
                statusMessage = "当前暂无可压缩的上下文"
                lastCompactionMessage = statusMessage
                return
            }
            let configuration = try await providerSettings.runtimeConfiguration(
                providerID: conversation.providerID,
                modelID: conversation.modelID
            )
            try Task.checkCancellation()
            let client = ProviderChatClientFactory.make(profile: configuration.profile)
            let request = AgentChatRequest(
                runID: UUID(),
                model: configuration.model.id,
                messages: ConversationContextCompaction.requestMessages(
                    existingSummary: conversation.contextSummary,
                    messagesToCompact: candidate.messages
                ),
                maxTokens: min(configuration.model.maxOutputTokens ?? 8_192, 8_192),
                reasoningEffort: conversation.reasoningEffort
            )
            let response = try await client.complete(request, apiKey: configuration.apiKey)
            try Task.checkCancellation()
            let summary = response.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try conversations.updateContextSummary(
                summary,
                cutoffSequence: candidate.cutoffSequence,
                for: conversation
            )
            statusMessage = "上下文已压缩"
            lastCompactionMessage = statusMessage
        } catch is CancellationError {
            statusMessage = "上下文压缩已取消"
            lastCompactionMessage = statusMessage
        } catch {
            let description = error.localizedDescription
            statusMessage = "上下文压缩失败"
            lastCompactionMessage = "上下文压缩失败：\(description)"
            lastCompactionFailed = true
            errorMessage = description
        }
    }

    func cancelCurrentTool(callID: String) async -> Bool {
        guard let currentRunner, let currentRunID else { return false }
        let didRequestStop = await currentRunner.cancelCurrentTool(
            runID: currentRunID,
            callID: callID
        )
        if didRequestStop {
            statusMessage = "正在停止当前工具…"
        }
        return didRequestStop
    }

    private func performRun(
        currentUserMessage: AgentMessage,
        conversation: ConversationRecord,
        appendUserMessage: Bool,
        continueMode: Bool,
        preparedConfiguration: ProviderRuntimeConfiguration? = nil
    ) async {
        runningConversationID = conversation.id
        statusMessage = "正在准备上下文…"
        errorMessage = nil
        latestUsage = .zero

        defer {
            if let currentRunID {
                toolActivity.endRun(runID: currentRunID)
            }
            currentRunner = nil
            currentRunID = nil
            runTask = nil
            runningConversationID = nil
        }

        do {
            try Task.checkCancellation()
            if appendUserMessage {
                try conversations.append(currentUserMessage, to: conversation)
            }
            try conversations.updateRunOutcome(
                status: .running,
                errorMessage: nil,
                usage: .zero,
                for: conversation
            )

            let configuration: ProviderRuntimeConfiguration
            if let preparedConfiguration {
                configuration = preparedConfiguration
            } else {
                configuration = try await providerSettings.runtimeConfiguration(
                    providerID: conversation.providerID,
                    modelID: conversation.modelID
                )
            }
            let history = try conversations.promptHistory(for: conversation)
            async let soul = soulStore.load()
            async let memory = memoryStore.promptContext()
            async let relevant = memoryStore.search(currentUserMessage.content ?? "", limit: 6)
            async let installedSkills = skillStore.list()
            async let resolvedSkills = skillStore.resolveMatches(
                userMessage: currentUserMessage.content ?? ""
            )
            async let availableTools = toolExecutor.availableTools()
            let (
                soulValue,
                memoryValue,
                relevantValue,
                installedSkillValues,
                resolvedSkillValues,
                toolDefinitions
            ) = try await (
                soul,
                memory,
                relevant,
                installedSkills,
                resolvedSkills,
                availableTools
            )
            try Task.checkCancellation()
            let contextWindow = configuration.model.contextWindow ?? 128_000
            let outputReserve = min(
                configuration.model.maxOutputTokens ?? max(512, contextWindow / 4),
                contextWindow
            )
            let inputBudget = max(0, contextWindow - outputReserve)
            let memoryByteBudget = min(24_000, max(0, inputBudget - 2_048)) * 2
            let soulByteBudget = min(4_096, max(256, inputBudget - 1_024)) * 2
            let prompt = promptBuilder.build(
                AgentSystemPromptContext(
                    soul: soulValue,
                    memory: memoryValue,
                    relevantMemories: relevantValue,
                    workspacePath: "/workspace",
                    workspace: AgentWorkspaceDescriptor(id: conversation.id.uuidString),
                    installedSkills: installedSkillValues,
                    resolvedSkills: resolvedSkillValues,
                    availableToolNames: configuration.model.supportsTools
                        ? toolDefinitions.map(\.name)
                        : []
                ),
                maximumMemoryUTF8Bytes: memoryByteBudget,
                maximumSoulUTF8Bytes: soulByteBudget,
                maximumSkillsUTF8Bytes: min(24_000, max(4_096, inputBudget * 2 / 5))
            )
            let systemMessages = [AgentMessage.system(prompt)]

            let runID = UUID()
            let runner = AgentRunner(
                client: ProviderChatClientFactory.make(profile: configuration.profile),
                toolExecutor: toolExecutor,
                maxRounds: 16
            )
            currentRunID = runID
            currentRunner = runner

            let input = AgentRunInput(
                runID: runID,
                conversationID: conversation.id,
                model: configuration.model.id,
                apiKey: configuration.apiKey,
                systemMessages: systemMessages,
                history: history,
                currentUserMessage: currentUserMessage,
                workspaceURL: workspacePaths.root,
                continueMode: continueMode,
                temperature: nil,
                maxTokens: configuration.model.maxOutputTokens,
                contextWindow: contextWindow,
                reasoningEffort: conversation.reasoningEffort,
                allowsToolCalls: configuration.model.supportsTools
            )

            let conversationID = conversation.id
            let result = try await runner.run(input) { [weak self] event in
                guard let self else { throw CancellationError() }
                try await self.handle(event, conversationID: conversationID)
            }
            latestUsage = result.usage
        } catch is CancellationError {
            statusMessage = "已取消"
            do {
                try persistInterruptedActiveTool(in: conversation)
                conversations.finalizeStreamingAssistants(
                    in: conversation,
                    status: .interrupted
                )
                try conversations.updateRunOutcome(
                    status: .cancelled,
                    errorMessage: nil,
                    usage: latestUsage,
                    for: conversation
                )
            } catch {
                errorMessage = "已取消，但无法保存会话状态：\(error.localizedDescription)"
            }
        } catch {
            let runErrorDescription = error.localizedDescription
            errorMessage = runErrorDescription
            statusMessage = "运行失败"
            do {
                conversations.finalizeStreamingAssistants(
                    in: conversation,
                    status: .failed
                )
                try conversations.updateRunOutcome(
                    status: .failed,
                    errorMessage: runErrorDescription,
                    usage: latestUsage,
                    for: conversation
                )
            } catch {
                errorMessage = "\(runErrorDescription)\n无法保存失败状态：\(error.localizedDescription)"
            }
        }
    }

    private func persistInterruptedActiveTool(
        in conversation: ConversationRecord
    ) throws {
        guard let snapshot = toolActivity.snapshot(for: conversation.id),
              let assistantMessageID = snapshot.activeAssistantMessageID,
              let callID = snapshot.activeCallID,
              let assistantRecord = conversation.messages.first(where: {
                  $0.id == assistantMessageID
              }),
              let assistant = try? assistantRecord.decodeMessage(),
              let call = assistant.toolCalls.first(where: { $0.id == callID }) else {
            return
        }
        let alreadyPersisted = conversation.messages.contains {
            $0.role == .tool
                && $0.toolCallID == callID
                && $0.sequence > assistantRecord.sequence
        }
        guard !alreadyPersisted else { return }

        let interruptedResult = AgentToolExecutionResult(
            content: "Agent 运行已取消，当前工具调用被中断。",
            isError: true,
            metadata: [
                "interrupted": .bool(true),
                "tool": .string(call.name),
            ]
        )
        try conversations.append(
            .tool(
                callID: call.id,
                name: call.name,
                content: try interruptedResult.modelContent()
            ),
            to: conversation,
            status: .failed
        )
        toolActivity.completeTool(callID: call.id, runID: snapshot.runID)
    }

    private func handle(_ event: AgentRunEvent, conversationID: UUID) async throws {
        guard let conversation = conversations.conversation(id: conversationID) else {
            throw ChatCoordinatorError.conversationNotFound(conversationID)
        }
        switch event {
        case let .started(runID):
            toolActivity.beginRun(runID: runID, conversationID: conversationID)
            statusMessage = "Agent 正在思考…"
        case let .requestStarted(round, attempt):
            statusMessage = attempt == 1 ? "第 \(round) 轮模型请求…" : "正在重试模型请求…"
        case let .assistantMessageStarted(id, _):
            try conversations.updateStreamingAssistant(
                id: id,
                snapshot: AgentStreamSnapshot(),
                in: conversation
            )
            if let currentRunID {
                toolActivity.registerAssistantMessage(id: id, runID: currentRunID)
            }
        case let .assistantMessageUpdated(id, snapshot, _):
            try conversations.updateStreamingAssistant(
                id: id,
                snapshot: snapshot,
                in: conversation
            )
        case let .assistantMessage(message, usage, contextWindow, _):
            latestUsage = latestUsage + usage
            try conversations.append(
                message,
                to: conversation,
                usage: usage,
                contextWindow: contextWindow
            )
            if let currentRunID {
                toolActivity.registerAssistantMessage(id: message.id, runID: currentRunID)
            }
        case let .toolStarted(call, _):
            if let currentRunID {
                toolActivity.beginTool(call, runID: currentRunID)
            }
            statusMessage = "正在调用 \(call.name)…"
        case let .toolCompleted(call, result, _):
            let content = try result.modelContent()
            let toolMessage = AgentMessage.tool(
                callID: call.id,
                name: call.name,
                content: content
            )
            try conversations.append(
                toolMessage,
                to: conversation,
                status: result.isError ? .failed : .completed
            )
            if let currentRunID {
                toolActivity.completeTool(callID: call.id, runID: currentRunID)
            }
            statusMessage = result.isError ? "工具返回错误，Agent 正在处理…" : "工具完成，Agent 正在继续…"
        case let .retrying(_, nextAttempt, errorDescription):
            statusMessage = "请求失败，准备第 \(nextAttempt) 次尝试…"
            errorMessage = errorDescription
        case let .completed(result):
            latestUsage = result.usage
            statusMessage = "完成"
            try conversations.updateRunOutcome(
                status: .completed,
                errorMessage: nil,
                usage: result.usage,
                for: conversation
            )
        case .cancelled:
            statusMessage = "已取消"
        }
    }
}
