import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent system prompt")
struct AgentSystemPromptBuilderTests {
    @Test("Injects SOUL, memory, workspace and deterministic time")
    func promptSections() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-10T08:00:47Z"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let context = AgentSystemPromptContext(
            soul: "Finish the task.",
            memory: MemoryPromptContext(
                longTermMemory: "- User likes Alpine",
                todayMemory: "- Rootfs is ready"
            ),
            relevantMemories: [
                MemorySearchHit(
                    id: "rootfs-1",
                    text: "Rootfs lives in Application Support",
                    source: .longTerm,
                    score: 2
                ),
            ],
            workspacePath: "/workspace",
            availableToolNames: ["context_time_now"],
            now: date,
            timeZone: utc,
            localeIdentifier: "zh_CN"
        )

        let prompt = AgentSystemPromptBuilder().build(context)
        #expect(prompt.contains("Finish the task."))
        #expect(prompt.contains("User likes Alpine"))
        #expect(prompt.contains("Rootfs is ready"))
        #expect(prompt.contains("/workspace"))
        #expect(prompt.contains("2026-07-10"))
        #expect(prompt.contains("context_time_now"))
        #expect(!prompt.contains("Current local time:"))
        #expect(!prompt.contains("2026-07-10T08:00:47Z"))
        #expect(prompt.contains("rootfs-1"))
    }

    @Test("Deterministically bounds Soul and memory injected into the system prompt")
    func boundedPromptContext() {
        let context = AgentSystemPromptContext(
            soul: String(repeating: "soul-value-", count: 2_000),
            memory: MemoryPromptContext(
                longTermMemory: String(repeating: "long-term-", count: 4_000),
                todayMemory: String(repeating: "today-", count: 4_000)
            ),
            relevantMemories: [
                MemorySearchHit(
                    id: "large-hit",
                    text: String(repeating: "relevant-", count: 4_000),
                    source: .longTerm,
                    score: 1
                ),
            ]
        )
        let builder = AgentSystemPromptBuilder()

        let first = builder.build(
            context,
            maximumMemoryUTF8Bytes: 900,
            maximumSoulUTF8Bytes: 300
        )
        let second = builder.build(
            context,
            maximumMemoryUTF8Bytes: 900,
            maximumSoulUTF8Bytes: 300
        )

        #expect(first == second)
        #expect(first.contains("已按模型上下文预算截断"))
        #expect(!first.contains(String(repeating: "long-term-", count: 100)))
        #expect(first.utf8.count < 8_000)
    }

    @Test("Only injects enabled authoritative skills and reports tool gating explicitly")
    func skillEnablementAndToolGating() {
        let enabled = skillEntry(id: "enabled-skill", enabled: true)
        let disabled = skillEntry(id: "disabled-skill", enabled: false)
        let context = AgentSystemPromptContext(
            soul: "Agent soul",
            memory: MemoryPromptContext(longTermMemory: "", todayMemory: ""),
            installedSkills: [enabled, disabled],
            resolvedSkills: [
                resolvedSkill(entry: disabled, body: "DISABLED_BODY_MUST_NOT_APPEAR"),
                resolvedSkill(entry: enabled, body: "ENABLED_BODY_MAY_APPEAR"),
            ],
            availableToolNames: [],
            localeIdentifier: "en_US"
        )

        let prompt = AgentSystemPromptBuilder().build(context)
        #expect(prompt.contains("ENABLED_BODY_MAY_APPEAR"))
        #expect(prompt.contains("enabled-skill"))
        #expect(!prompt.contains("DISABLED_BODY_MUST_NOT_APPEAR"))
        #expect(!prompt.contains("disabled-skill"))
        #expect(prompt.contains("Available tools: (none)"))
        #expect(prompt.contains("No tools are enabled for the current model"))
        #expect(!prompt.contains("`file_write`"))
        #expect(!prompt.contains("`terminal_execute`"))
        #expect(!prompt.contains("`skills_read`"))
        #expect(!prompt.contains("`memory_write_daily`"))
        #expect(!prompt.contains("runtime-provided"))
    }

    @Test("Caps automatic skill injection at two 1200-character summaries")
    func boundedAutomaticSkillInjection() {
        let first = skillEntry(id: "first-skill", enabled: true)
        let second = skillEntry(id: "second-skill", enabled: true)
        let third = skillEntry(id: "third-skill", enabled: true)
        let context = AgentSystemPromptContext(
            soul: "Agent soul",
            memory: MemoryPromptContext(longTermMemory: "", todayMemory: ""),
            installedSkills: [first, second, third],
            resolvedSkills: [
                resolvedSkill(
                    entry: first,
                    body: "FIRST_BODY " + String(repeating: "x", count: 3_000) + " FIRST_TAIL"
                ),
                resolvedSkill(entry: second, body: "SECOND_BODY"),
                resolvedSkill(entry: third, body: "THIRD_BODY_MUST_NOT_APPEAR"),
            ],
            availableToolNames: ["skills_list", "skills_read"],
            localeIdentifier: "en_US"
        )

        let prompt = AgentSystemPromptBuilder().build(context)
        #expect(prompt.contains("FIRST_BODY"))
        #expect(prompt.contains("SECOND_BODY"))
        #expect(!prompt.contains("FIRST_TAIL"))
        #expect(!prompt.contains("THIRD_BODY_MUST_NOT_APPEAR"))
    }

    @Test("Browser guidance states ephemeral isolation and shared manual takeover")
    func browserCapabilityGuidance() {
        let context = AgentSystemPromptContext(
            soul: "Agent soul",
            memory: MemoryPromptContext(longTermMemory: "", todayMemory: ""),
            availableToolNames: ["browser_use"],
            localeIdentifier: "en_US"
        )

        let prompt = AgentSystemPromptBuilder().build(context)
        #expect(prompt.contains("website data is non-persistent"))
        #expect(prompt.contains("resets when the conversation changes"))
        #expect(prompt.contains("same WebKit session shown in the chat's visible browser card"))
        #expect(prompt.contains("complete verification manually"))
        #expect(prompt.contains("before continuing"))
    }

    @Test("HealthKit guidance requires explicit current-turn consent")
    func healthKitPrivacyGuidance() {
        let context = AgentSystemPromptContext(
            soul: "Agent soul",
            memory: MemoryPromptContext(longTermMemory: "", todayMemory: ""),
            availableToolNames: [
                "healthkit_data_types",
                "healthkit_quantity_statistics",
            ],
            localeIdentifier: "en_US"
        )

        let prompt = AgentSystemPromptBuilder().build(context)
        #expect(prompt.contains("HealthKit data is highly sensitive"))
        #expect(prompt.contains("user's current request explicitly asks"))
        #expect(prompt.contains("Never infer consent from history or memory"))
        #expect(prompt.contains("Query tools never present authorization UI"))
        #expect(prompt.contains("stop the tool loop"))
        #expect(prompt.contains("only after a later user message"))
        #expect(prompt.contains("empty result may mean no data or no read permission"))
    }

    @Test("Personal tool guidance does not mention unadvertised alarm tools")
    func personalToolGuidanceMatchesAdvertisedTools() {
        let context = AgentSystemPromptContext(
            soul: "Agent soul",
            memory: MemoryPromptContext(longTermMemory: "", todayMemory: ""),
            availableToolNames: ["calendar_list", "contacts_search"],
            platformName: "macOS",
            localeIdentifier: "en_US"
        )

        let prompt = AgentSystemPromptBuilder().build(context)

        #expect(prompt.contains("use `calendar_*` for system calendars"))
        #expect(prompt.contains("use `contacts_*` for the address book"))
        #expect(!prompt.contains("`alarm_reminder_*`"))
        #expect(!prompt.contains("`clock_app`"))
    }

    private func skillEntry(id: String, enabled: Bool) -> AgentSkillIndexEntry {
        AgentSkillIndexEntry(
            id: id,
            name: id,
            description: "Skill \(id)",
            compatibility: "apple",
            metadata: [:],
            rootPath: "/workspace/.omnibot/skills/\(id)",
            skillFilePath: "/workspace/.omnibot/skills/\(id)/SKILL.md",
            hasScripts: false,
            hasReferences: false,
            hasAssets: false,
            hasEvals: false,
            enabled: enabled
        )
    }

    private func resolvedSkill(
        entry: AgentSkillIndexEntry,
        body: String
    ) -> ResolvedAgentSkill {
        ResolvedAgentSkill(
            entry: entry,
            frontmatter: ["name": entry.name],
            bodyMarkdown: body,
            referencePaths: [],
            scriptsPath: nil,
            assetsPath: nil,
            triggerReason: "test match"
        )
    }
}
