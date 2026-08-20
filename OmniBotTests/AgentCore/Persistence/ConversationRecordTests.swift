import Foundation
import SwiftData
import Testing
@testable import Via_Vera

@Suite("Conversation persistence")
struct ConversationRecordTests {
    @Test("Empty drafts stay out of history until their first message")
    @MainActor
    func emptyDraftHistoryVisibility() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let repository = ConversationRepository(modelContext: context)

        let draft = try repository.createConversation(
            providerID: "provider",
            modelID: "model"
        )

        #expect(repository.historyConversations.isEmpty)
        #expect(repository.draftConversation?.id == draft.id)

        try repository.append(.user("First message"), to: draft)

        #expect(repository.historyConversations.map(\.id) == [draft.id])
        #expect(repository.draftConversation == nil)
    }

    @Test("SwiftData preserves assistant tool calls and role=tool payloads")
    @MainActor
    func toolTranscriptRoundTrip() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(modelID: "test-model")
        context.insert(conversation)

        let call = AgentToolCall(
            id: "call_persisted",
            name: "file_read",
            arguments: #"{"path":"notes.txt"}"#
        )
        try conversation.append(.assistant(toolCalls: [call]))
        try conversation.append(.tool(
            callID: call.id,
            name: call.name,
            content: #"{"success":true,"content":"hello"}"#
        ))
        try context.save()

        let reloadedContext = ModelContext(container)
        let descriptor = FetchDescriptor<ConversationRecord>()
        let reloaded = try #require(try reloadedContext.fetch(descriptor).first)
        let messages = try reloaded.orderedMessages.map { try $0.decodeMessage() }

        #expect(messages.count == 2)
        #expect(messages[0].toolCalls == [call])
        #expect(messages[1].role == .tool)
        #expect(messages[1].toolCallID == call.id)
        #expect(messages[1].content?.contains("hello") == true)
    }

    @Test("SwiftData preserves terminal run error and token usage")
    @MainActor
    func runOutcomeRoundTrip() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let usage = AgentUsage(
            promptTokens: 100,
            completionTokens: 25,
            totalTokens: 125,
            cachedTokens: 60,
            cacheCreationTokens: 20,
            reportsCacheUsage: true
        )
        let conversation = ConversationRecord(
            modelID: "test-model",
            status: .failed,
            lastErrorMessage: "provider failed",
            usage: usage
        )
        context.insert(conversation)
        try context.save()

        let reloadedContext = ModelContext(container)
        let descriptor = FetchDescriptor<ConversationRecord>()
        let reloaded = try #require(try reloadedContext.fetch(descriptor).first)
        #expect(reloaded.status == .failed)
        #expect(reloaded.lastErrorMessage == "provider failed")
        #expect(reloaded.usage == usage)
    }

    @Test("Legacy cache counters imply cache telemetry")
    @MainActor
    func legacyCacheCountersRemainVisible() {
        let conversation = ConversationRecord(modelID: "test-model")
        conversation.cachedTokens = 40
        conversation.reportsCacheUsage = false

        #expect(conversation.usage.cachedTokens == 40)
        #expect(conversation.usage.reportsCacheUsage)
    }

    @Test("Startup recovers stale running conversations without losing usage")
    @MainActor
    func interruptedRunRecovery() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let usage = AgentUsage(promptTokens: 21, completionTokens: 5, totalTokens: 26)
        let running = ConversationRecord(
            modelID: "test-model",
            status: .running,
            usage: usage
        )
        let completed = ConversationRecord(
            modelID: "test-model",
            status: .completed,
            lastErrorMessage: nil
        )
        context.insert(running)
        context.insert(completed)
        try context.save()

        let repository = ConversationRepository(modelContext: context)
        try repository.reload()
        let recoveryDate = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(try repository.recoverInterruptedRuns(at: recoveryDate) == 1)

        let recovered = try #require(repository.conversation(id: running.id))
        #expect(recovered.status == .failed)
        #expect(recovered.lastErrorMessage == ConversationRepository.interruptedRunMessage)
        #expect(recovered.usage == usage)
        #expect(recovered.updatedAt == recoveryDate)
        #expect(repository.conversation(id: completed.id)?.status == .completed)
    }

    @Test("Startup settles a persisted tool intent as outcome unknown")
    @MainActor
    func interruptedToolIntentRecovery() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(modelID: "test-model", status: .running)
        context.insert(conversation)
        try context.save()

        let repository = ConversationRepository(modelContext: context)
        try repository.reload()
        let active = try #require(repository.conversation(id: conversation.id))
        let call = AgentToolCall(id: "call-pending", name: "file_write", arguments: "{}")
        try repository.append(.assistant(toolCalls: [call]), to: active)
        let refreshed = try #require(repository.conversation(id: conversation.id))
        let checkpointID = UUID()
        try repository.append(
            .tool(
                callID: call.id,
                name: call.name,
                content: "intent persisted",
                id: checkpointID
            ),
            to: refreshed,
            status: .pending
        )

        #expect(try repository.recoverInterruptedRuns() == 1)
        let recovered = try #require(repository.conversation(id: conversation.id))
        let checkpoint = try #require(
            recovered.orderedMessages.first(where: { $0.id == checkpointID })
        )
        #expect(checkpoint.status == .interrupted)
        #expect(checkpoint.toolCallID == call.id)
        #expect(checkpoint.content?.contains("外部副作用是否发生未知") == true)
        #expect(checkpoint.content?.contains("outcomeUnknown") == true)
    }

    @Test("Pinned conversations persist and sort ahead of newer conversations")
    @MainActor
    func pinnedConversationPersistenceAndOrdering() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let older = ConversationRecord(
            title: "Older",
            modelID: "test-model",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ConversationRecord(
            title: "Newer",
            modelID: "test-model",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let repository = ConversationRepository(modelContext: context)
        try repository.reload()
        #expect(repository.conversations.map(\.id) == [newer.id, older.id])

        try repository.setPinned(true, for: older)
        #expect(repository.conversations.map(\.id) == [older.id, newer.id])

        let reloadedContext = ModelContext(container)
        let reloadedRepository = ConversationRepository(modelContext: reloadedContext)
        try reloadedRepository.reload()
        #expect(reloadedRepository.conversation(id: older.id)?.isPinned == true)
        #expect(reloadedRepository.conversations.map(\.id) == [older.id, newer.id])

        let reloadedOlder = try #require(reloadedRepository.conversation(id: older.id))
        try reloadedRepository.setPinned(false, for: reloadedOlder)
        #expect(reloadedRepository.conversation(id: older.id)?.isPinned == false)
        #expect(reloadedRepository.conversations.map(\.id) == [newer.id, older.id])
    }

    @Test("Conversation titles can be renamed and persist")
    @MainActor
    func conversationRenamePersistence() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(title: "Old title", modelID: "test-model")
        context.insert(conversation)
        try context.save()

        let repository = ConversationRepository(modelContext: context)
        try repository.reload()
        let storedConversation = try #require(repository.conversation(id: conversation.id))

        try repository.rename(storedConversation, to: "  Focused title\n")
        #expect(repository.conversation(id: conversation.id)?.title == "Focused title")

        let reloadedContext = ModelContext(container)
        let reloadedRepository = ConversationRepository(modelContext: reloadedContext)
        try reloadedRepository.reload()
        #expect(reloadedRepository.conversation(id: conversation.id)?.title == "Focused title")
    }

    @Test("Blank titles do not replace an existing conversation title")
    @MainActor
    func blankConversationRenameIsIgnored() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(title: "Keep this title", modelID: "test-model")
        context.insert(conversation)
        try context.save()

        let repository = ConversationRepository(modelContext: context)
        try repository.reload()
        let storedConversation = try #require(repository.conversation(id: conversation.id))

        try repository.rename(storedConversation, to: "  \n")
        #expect(repository.conversation(id: conversation.id)?.title == "Keep this title")
    }

    @Test("Reasoning effort and compacted prompt history persist per conversation")
    @MainActor
    func compactedPromptHistoryPersistence() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let repository = ConversationRepository(modelContext: context)
        let conversation = try repository.createConversation(
            providerID: "provider",
            modelID: "model"
        )

        try repository.append(.user("First request"), to: conversation)
        try repository.append(.assistant("First answer"), to: conversation)
        let latestUser = try repository.append(.user("Latest request"), to: conversation)
        let latestAssistant = try repository.append(.assistant("Latest answer"), to: conversation)

        let candidate = try #require(
            try repository.contextCompactionCandidate(for: conversation)
        )
        #expect(candidate.messages.compactMap(\.content) == ["First request", "First answer"])
        #expect(candidate.cutoffSequence == 1)

        try repository.updateContextSummary(
            "Earlier work was completed.",
            cutoffSequence: candidate.cutoffSequence,
            for: conversation
        )
        let updated = try #require(repository.conversation(id: conversation.id))
        try repository.updateReasoningEffort(.max, for: updated)

        let reloaded = try #require(repository.conversation(id: conversation.id))
        let promptHistory = try repository.promptHistory(for: reloaded)
        #expect(reloaded.reasoningEffort == .max)
        #expect(reloaded.contextCutoffSequence == 1)
        #expect(promptHistory.count == 3)
        #expect(promptHistory[0].content?.hasPrefix(ConversationContextCompaction.summaryPrefix) == true)
        #expect(promptHistory[1].id == latestUser.id)
        #expect(promptHistory[2].id == latestAssistant.id)

        try repository.append(.user("Third request"), to: reloaded)
        let repeatedCandidate = try #require(
            try repository.contextCompactionCandidate(for: reloaded)
        )
        #expect(repeatedCandidate.messages.map(\.id) == [latestUser.id, latestAssistant.id])
        #expect(repeatedCandidate.cutoffSequence == latestAssistant.sequence)
    }

    @Test("Replacing the latest user turn preserves earlier history and removes its outputs")
    @MainActor
    func replaceLatestUserTurn() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(
            title: "Original title",
            modelID: "test-model",
            status: .completed,
            usage: AgentUsage(promptTokens: 30, completionTokens: 10, totalTokens: 40)
        )
        context.insert(conversation)
        try context.save()
        let repository = ConversationRepository(modelContext: context)
        try repository.reload()

        let firstUser = try repository.append(.user("First"), to: conversation)
        let firstAssistant = try repository.append(.assistant("First answer"), to: conversation)
        let latestUser = try repository.append(.user("Second"), to: conversation)
        try repository.append(.assistant("Old second answer"), to: conversation)

        let replacement = try repository.replaceLatestUserTurn(
            messageID: latestUser.id,
            with: "Edited second",
            in: conversation
        )
        let reloaded = try #require(repository.conversation(id: conversation.id))

        #expect(replacement.id == latestUser.id)
        #expect(replacement.content == "Edited second")
        #expect(reloaded.orderedMessages.map(\.id) == [firstUser.id, firstAssistant.id, latestUser.id])
        #expect(try reloaded.orderedMessages.last?.decodeMessage().content == "Edited second")
        #expect(reloaded.status == .idle)
        #expect(reloaded.usage == .zero)
        #expect(reloaded.lastErrorMessage == nil)
        #expect(reloaded.title == "First")
    }

    @Test("Only the latest user message can be replaced")
    @MainActor
    func rejectsOlderUserTurnReplacement() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(modelID: "test-model")
        context.insert(conversation)
        try context.save()
        let repository = ConversationRepository(modelContext: context)
        try repository.reload()

        let olderUser = try repository.append(.user("Older"), to: conversation)
        try repository.append(.assistant("Answer"), to: conversation)
        try repository.append(.user("Latest"), to: conversation)

        #expect(throws: ChatCoordinatorError.self) {
            try repository.replaceLatestUserTurn(
                messageID: olderUser.id,
                with: "Should fail",
                in: conversation
            )
        }
    }

    @Test("Editing the first user message refreshes the conversation title")
    @MainActor
    func firstUserEditUpdatesTitle() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ConversationRecord.self,
            MessageRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let conversation = ConversationRecord(modelID: "test-model")
        context.insert(conversation)
        try context.save()
        let repository = ConversationRepository(modelContext: context)
        try repository.reload()

        let user = try repository.append(.user("Old title"), to: conversation)
        try repository.append(.assistant("Old answer"), to: conversation)
        try repository.replaceLatestUserTurn(
            messageID: user.id,
            with: "A refreshed conversation title",
            in: conversation
        )

        #expect(repository.conversation(id: conversation.id)?.title == "A refreshed conversation title")
    }

    @Test("A failed latest-turn save rolls back and attempts to refresh")
    @MainActor
    func latestUserTurnSaveFailureRollsBack() {
        var events: [String] = []

        do {
            _ = try ConversationRepository.commitLatestUserTurnReplacement(
                save: {
                    events.append("save")
                    throw ReplacementPersistenceError.save
                },
                rollback: {
                    events.append("rollback")
                },
                reload: {
                    events.append("reload")
                    throw ReplacementPersistenceError.reload
                }
            )
            Issue.record("Expected the save error to be rethrown")
        } catch {
            #expect(error as? ReplacementPersistenceError == .save)
        }

        #expect(events == ["save", "rollback", "reload"])
    }

    @Test("A refresh failure after commit does not report the replacement as failed")
    @MainActor
    func latestUserTurnReloadFailureDoesNotUndoCommit() throws {
        var events: [String] = []

        let outcome = try ConversationRepository.commitLatestUserTurnReplacement(
            save: {
                events.append("save")
            },
            rollback: {
                events.append("rollback")
            },
            reload: {
                events.append("reload")
                throw ReplacementPersistenceError.reload
            }
        )

        #expect(outcome == .committedWithoutRefresh)
        #expect(events == ["save", "reload"])
    }

    private enum ReplacementPersistenceError: Error {
        case save
        case reload
    }
}
