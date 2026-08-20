import Foundation

nonisolated public struct AgentSystemPromptBuilder: Sendable {
    public init() {}

    public func build(
        _ context: AgentSystemPromptContext,
        maximumMemoryUTF8Bytes: Int = 48_000,
        maximumSoulUTF8Bytes: Int = 8_192,
        maximumSkillsUTF8Bytes: Int = 24_000
    ) -> String {
        let unboundedLongTerm = nonEmpty(
            context.memory.longTermMemory,
            fallback: "（暂无长期记忆）"
        )
        let unboundedToday = nonEmpty(
            context.memory.todayMemory,
            fallback: "（今天暂无短期记忆）"
        )
        let unboundedRelevant = context.relevantMemories.isEmpty
            ? "（没有额外检索结果）"
            : context.relevantMemories.map { "- [\($0.id)] \($0.text)" }.joined(separator: "\n")
        let memorySections = boundedSections(
            [unboundedLongTerm, unboundedToday, unboundedRelevant],
            totalUTF8ByteLimit: maximumMemoryUTF8Bytes
        )
        let longTerm = memorySections[0]
        let today = memorySections[1]
        let relevant = memorySections[2]
        let soul = truncated(
            nonEmpty(context.soul, fallback: SoulStore.defaultSoul),
            maximumUTF8Bytes: maximumSoulUTF8Bytes
        )
        let enabledInstalledSkills = context.installedSkills
            .filter(\.enabled)
            .sorted { $0.id < $1.id }
        let enabledSkillIDs = Set(enabledInstalledSkills.map(\.id))
        var loadedSkillIDs = Set<String>()
        let enabledResolvedSkills = context.resolvedSkills.filter { skill in
            skill.entry.enabled
                && enabledSkillIDs.contains(skill.entry.id)
                && loadedSkillIDs.insert(skill.entry.id).inserted
        }
        .prefix(2)
        let installedSkills = installedSkillIndex(enabledInstalledSkills)
        let loadedSkills = truncated(
            enabledResolvedSkills.isEmpty
                ? emptyLoadedSkills(localeIdentifier: context.localeIdentifier)
                : enabledResolvedSkills
                    .map { $0.promptSummary(maximumCharacters: 1_200) }
                    .joined(separator: "\n\n---\n\n"),
            maximumUTF8Bytes: maximumSkillsUTF8Bytes
        )
        let toolNames = context.availableToolNames.isEmpty
            ? "(none)"
            : context.availableToolNames.sorted().joined(separator: ", ")
        let platformRules = platformToolRules(
            availableToolNames: context.availableToolNames,
            platformName: context.platformName,
            localeIdentifier: context.localeIdentifier
        )
        let workspaceRules = workspaceToolRules(
            availableToolNames: context.availableToolNames,
            workspaceRoot: context.workspace.rootPath,
            localeIdentifier: context.localeIdentifier
        )
        let skillRules = skillToolRules(
            availableToolNames: context.availableToolNames,
            localeIdentifier: context.localeIdentifier
        )
        let memoryRules = memoryToolRules(
            availableToolNames: context.availableToolNames,
            localeIdentifier: context.localeIdentifier
        )

        if context.localeIdentifier.lowercased().hasPrefix("zh") {
            return chinesePrompt(
                context: context,
                soul: soul,
                longTerm: longTerm,
                today: today,
                relevant: relevant,
                installedSkills: installedSkills,
                loadedSkills: loadedSkills,
                toolNames: toolNames,
                platformRules: platformRules,
                workspaceRules: workspaceRules,
                skillRules: skillRules,
                memoryRules: memoryRules
            )
        }
        return englishPrompt(
            context: context,
            soul: soul,
            longTerm: longTerm,
            today: today,
            relevant: relevant,
            installedSkills: installedSkills,
            loadedSkills: loadedSkills,
            toolNames: toolNames,
            platformRules: platformRules,
            workspaceRules: workspaceRules,
            skillRules: skillRules,
            memoryRules: memoryRules
        )
    }

    private func chinesePrompt(
        context: AgentSystemPromptContext,
        soul: String,
        longTerm: String,
        today: String,
        relevant: String,
        installedSkills: String,
        loadedSkills: String,
        toolNames: String,
        platformRules: String,
        workspaceRules: String,
        skillRules: String,
        memoryRules: String
    ) -> String {
        """
        你是运行在 \(context.platformName) 本地 Alpine 工作空间中的 AI Agent。你的目标是可靠地完成用户任务，而不是只描述可能的做法。使用与用户相同的语言回复。

        <soul>
        \(soul)
        </soul>

        <time_context>
        本地日期：\(localDateString(context.now, timeZone: context.timeZone))
        星期：\(weekdayString(context.now, timeZone: context.timeZone, localeIdentifier: context.localeIdentifier))
        时区：\(context.timeZone.identifier)
        Locale：\(context.localeIdentifier)
        这段粗粒度时间上下文由运行时缓存，仅用于解释“今天”“明天”等相对日期，不是用户原文或长期记忆。
        \(context.availableToolNames.contains("context_time_now")
            ? "需要精确的当前时间时调用 `context_time_now`；不要把这里的日期当作精确时钟。"
            : "本轮没有精确时间工具；需要精确时钟时应明确说明当前无法可靠获取。")
        </time_context>

        <workspace>
        - conversationContextId: \(context.workspace.id)
        - shellWorkspaceRoot: \(context.workspace.rootPath)
        - shellCurrentCwd: \(context.workspace.currentWorkingDirectory)
        - uriRoot: \(context.workspace.resourceRoot)
        - attachmentsPath: \(context.workspace.attachmentsPath)
        - skillsPath: \(context.workspace.skillsPath)
        - browserPath: \(context.workspace.browserPath)
        - offloadsPath: \(context.workspace.offloadsPath)
        - retentionPolicy: \(context.workspace.retentionPolicy)
        </workspace>

        <workspace_rules>
        \(workspaceRules)
        </workspace_rules>

        <platform_tool_rules>
        \(platformRules)
        - 当前可用工具：\(toolNames)
        </platform_tool_rules>

        <skills>
        已启用的 skills 索引（索引不等于正文已加载）：
        \(installedSkills)

        当前已加载的 skills 正文：
        \(loadedSkills)

        \(skillRules)
        </skills>

        <memory_rules>
        \(memoryRules)
        </memory_rules>

        <long_term_memory>
        \(longTerm)
        </long_term_memory>

        <today_memory>
        \(today)
        </today_memory>

        <relevant_memory>
        \(relevant)
        </relevant_memory>
        """
    }

    private func englishPrompt(
        context: AgentSystemPromptContext,
        soul: String,
        longTerm: String,
        today: String,
        relevant: String,
        installedSkills: String,
        loadedSkills: String,
        toolNames: String,
        platformRules: String,
        workspaceRules: String,
        skillRules: String,
        memoryRules: String
    ) -> String {
        """
        You are an AI Agent operating in a local Alpine workspace on \(context.platformName). Reliably complete the user's task instead of merely describing possible steps. Reply in the user's language.

        <soul>
        \(soul)
        </soul>

        <time_context>
        Local date: \(localDateString(context.now, timeZone: context.timeZone))
        Day of week: \(weekdayString(context.now, timeZone: context.timeZone, localeIdentifier: context.localeIdentifier))
        Timezone: \(context.timeZone.identifier)
        Locale: \(context.localeIdentifier)
        This coarse runtime context is cached and only interprets relative dates such as today and tomorrow. It is not user-authored text or long-term memory.
        \(context.availableToolNames.contains("context_time_now")
            ? "Call `context_time_now` when exact current time matters; do not treat this date as an exact clock."
            : "No exact-time tool is available this turn; state that exact current time cannot be retrieved reliably when it matters.")
        </time_context>

        <workspace>
        - conversationContextId: \(context.workspace.id)
        - shellWorkspaceRoot: \(context.workspace.rootPath)
        - shellCurrentCwd: \(context.workspace.currentWorkingDirectory)
        - uriRoot: \(context.workspace.resourceRoot)
        - attachmentsPath: \(context.workspace.attachmentsPath)
        - skillsPath: \(context.workspace.skillsPath)
        - browserPath: \(context.workspace.browserPath)
        - offloadsPath: \(context.workspace.offloadsPath)
        - retentionPolicy: \(context.workspace.retentionPolicy)
        </workspace>

        <workspace_rules>
        \(workspaceRules)
        </workspace_rules>

        <platform_tool_rules>
        \(platformRules)
        - Available tools: \(toolNames)
        </platform_tool_rules>

        <skills>
        Enabled skills index (index metadata does not mean the body is loaded):
        \(installedSkills)

        Loaded skill bodies for this turn:
        \(loadedSkills)

        \(skillRules)
        </skills>

        <memory_rules>
        \(memoryRules)
        </memory_rules>

        <long_term_memory>
        \(longTerm)
        </long_term_memory>

        <today_memory>
        \(today)
        </today_memory>

        <relevant_memory>
        \(relevant)
        </relevant_memory>
        """
    }

    private func platformToolRules(
        availableToolNames: [String],
        platformName: String,
        localeIdentifier: String
    ) -> String {
        let names = Set(availableToolNames)
        let isChinese = localeIdentifier.lowercased().hasPrefix("zh")
        guard !names.isEmpty else {
            if isChinese {
                return """
                - 当前模型未启用任何工具。不要暗示或声称已经调用工具；需要外部操作时向用户说明限制。
                - 本 Apple 版本不提供 Android VLM、Shizuku、AccessibilityService 或 Android App deep-link 工具，不要臆造这些能力。
                """
            }
            return """
            - No tools are enabled for the current model. Do not imply or claim tool use; explain the limitation when external action is required.
            - This Apple build does not expose Android VLM, Shizuku, AccessibilityService, or Android app deep-link tools. Never invent those capabilities.
            """
        }

        var lines: [String] = []
        if names.contains("browser_use") {
            lines.append(isChinese
                ? "- 网页浏览、提取与交互优先使用 `browser_use`。它与聊天页面可见的浏览器卡片共享同一个 WebKit 会话，使用 Safari 同源引擎，但不是 Safari App，也不会读取 Safari 的私有标签页或 Cookie；网站数据不持久化，并在切换对话时重置。先 `navigate`，再按需提取、查找、点击、输入或截图；一次调用只做一个 action。浏览器结果含 `riskChallengeDetected=true` 时停止自动交互，请用户在同一会话的浏览器卡片内手动完成验证后再继续。"
                : "- Prefer `browser_use` for web navigation, extraction, and interaction. It shares the same WebKit session shown in the chat's visible browser card, uses Safari's engine, is not the Safari app, and cannot read Safari's private tabs or cookies; website data is non-persistent and resets when the conversation changes. Perform one action per call. When `riskChallengeDetected=true`, stop automated interaction and ask the user to complete verification manually in that same session's browser card before continuing.")
        }
        var personalToolSemantics: [String] = []
        if names.contains(where: { $0.hasPrefix("alarm_reminder_") }) {
            let alarmSemantics: String
            if platformName.localizedCaseInsensitiveContains("iOS") {
                alarmSemantics = isChinese
                    ? "`alarm_reminder_*` 的 `exact_alarm` 由 AlarmKit 实现"
                    : "`alarm_reminder_*` uses AlarmKit for `exact_alarm`"
            } else if platformName.localizedCaseInsensitiveContains("macOS") {
                alarmSemantics = isChinese
                    ? "`alarm_reminder_*` 在 macOS 降级为通知提醒，结果会标记 `degraded=true`"
                    : "`alarm_reminder_*` degrades to notification reminders on macOS and reports `degraded=true`"
            } else {
                alarmSemantics = isChinese
                    ? "`alarm_reminder_*` 使用当前 Apple 平台可用的提醒后端"
                    : "`alarm_reminder_*` uses the reminder backend available on the current Apple platform"
            }
            personalToolSemantics.append(alarmSemantics)
            personalToolSemantics.append(isChinese
                ? "`clock_app` 不受支持"
                : "`clock_app` is unsupported")
        }
        if names.contains(where: { $0.hasPrefix("calendar_") }) {
            personalToolSemantics.append(isChinese
                ? "`calendar_*` 用于系统日历"
                : "use `calendar_*` for system calendars")
        }
        if names.contains(where: { $0.hasPrefix("contacts_") }) {
            personalToolSemantics.append(isChinese
                ? "`contacts_*` 用于通讯录"
                : "use `contacts_*` for the address book")
        }
        if !personalToolSemantics.isEmpty {
            let separator = isChinese ? "；" : "; "
            let sentenceSeparator = isChinese ? "。" : ". "
            let permissionGuidance = isChinese
                ? "权限拒绝后不要循环重试，应说明需要用户在系统设置中授权。"
                : "Do not loop on denied permissions; explain that authorization must be changed in System Settings."
            lines.append(
                "- \(personalToolSemantics.joined(separator: separator))\(sentenceSeparator)\(permissionGuidance)"
            )
        }
        if names.contains(where: { $0.hasPrefix("healthkit_") }) {
            lines.append(isChinese
                ? "- HealthKit 数据高度敏感，查询结果会进入当前配置模型的上下文。`healthkit_data_types` 可用于说明能力；其他 `healthkit_*` 仅在用户本轮明确要求访问对应健康数据时调用，不能从历史对话或记忆推断同意，也不能主动探查。查询工具不会自动弹出授权页；收到 `authorization_required` 时调用一次 `healthkit_request_access`。如果结果为 `authorizationPending=true`，必须停止工具循环并请用户完成系统授权页，只能在用户后续新消息后再查询。HealthKit 不披露逐类型读取授权状态，空结果可能是没有数据或未授予读取权限，不要循环重试或断言权限状态。"
                : "- HealthKit data is highly sensitive, and query results enter the configured model's context. `healthkit_data_types` may be used to explain capabilities; call every other `healthkit_*` tool only when the user's current request explicitly asks to access the corresponding health data. Never infer consent from history or memory, and never probe proactively. Query tools never present authorization UI; on `authorization_required`, call `healthkit_request_access` once. If it returns `authorizationPending=true`, stop the tool loop and ask the user to finish the system sheet, then query only after a later user message. HealthKit does not disclose per-type read authorization, so an empty result may mean no data or no read permission; do not retry in a loop or claim an authorization state.")
        }
        lines.append(isChinese
            ? "- 本 Apple 版本不提供 Android VLM、Shizuku、AccessibilityService 或 Android App deep-link 工具，不要臆造这些能力。"
            : "- This Apple build does not expose Android VLM, Shizuku, AccessibilityService, or Android app deep-link tools. Never invent those capabilities.")
        return lines.joined(separator: "\n")
    }

    private func workspaceToolRules(
        availableToolNames: [String],
        workspaceRoot: String,
        localeIdentifier: String
    ) -> String {
        let names = Set(availableToolNames)
        let isChinese = localeIdentifier.lowercased().hasPrefix("zh")
        var lines = isChinese
            ? [
                "- 整个 \(workspaceRoot) 是用户与 Agent 共享的工作区；需要隔离时显式创建子目录，不要假设每个会话都有独立目录。",
                "- provider、凭据、SOUL 与记忆源文件属于受保护的 Apple 宿主控制数据，不得越权访问。",
                "- 已有结果资源使用 `omnibot://` URI。原样复用 artifact 的 `renderMarkdown`，不猜测或改写 URI；图片用 `![说明](omnibot://...)`，其他文件用 `[名称](omnibot://...)`。",
            ]
            : [
                "- The whole \(workspaceRoot) is shared by the user and Agent. Create subdirectories explicitly when isolation is needed; do not assume per-conversation roots.",
                "- Provider settings, credentials, SOUL, and memory source files are protected Apple-host control data. Never attempt unauthorized access.",
                "- Existing result resources use `omnibot://` URIs. Reuse an artifact's `renderMarkdown` exactly and never guess or rewrite its URI; use `![caption](omnibot://...)` for images and `[name](omnibot://...)` for other files.",
            ]

        let fileTools = names.filter { $0.hasPrefix("file_") }
        if !fileTools.isEmpty {
            lines.append(isChinese
                ? "- 只在允许的 workspace 路径内使用当前可用的 `file_*` 工具；创建用 `file_write`，修改用 `file_edit`，读取、搜索、列目录和元信息分别用对应工具。"
                : "- Use only the currently available `file_*` tools and remain inside allowed workspace paths. Prefer `file_write` for creation and `file_edit` for modifications; use the matching read, search, list, and stat tools for inspection.")
        }
        if names.contains("terminal_execute") {
            lines.append(isChinese
                ? "- `terminal_execute` 是一次性非交互命令的默认选择；只有确实需要保留 cwd、环境或中间状态，且 `terminal_session_*` 可用时，才使用持久会话。"
                : "- `terminal_execute` is the default for one-shot non-interactive commands. Use `terminal_session_*` only when those tools are available and persistent cwd, environment, or intermediate state is genuinely required.")
            lines.append(isChinese
                ? "- 终端输出较长时，优先引用工具返回的 offload artifact，不要在最终回复中粘贴大段原文。"
                : "- When terminal output is long, prefer the returned offload artifact instead of pasting a large raw transcript into the final response.")
        }
        if names.isEmpty {
            lines.append(isChinese
                ? "- 本轮 workspace 信息只作为上下文；不能读写文件、执行命令或创建 artifact，也不得声称已完成这些动作。"
                : "- Workspace information is context-only for this turn. You cannot read or write files, execute commands, or create artifacts, and must not claim to have done so.")
        } else {
            lines.append(isChinese
                ? "- 只能调用“当前可用工具”中列出的能力；每次调用后等待并检查结果，不要声称执行了尚未得到结果的动作。工具有 `tool_title` 时，用用户语言简短描述且不包含秘密。"
                : "- Call only capabilities listed under Available tools. Wait for and inspect each result, never claim an action before receiving it, and keep `tool_title` concise, in the user's language, and free of secrets when that field is present.")
        }
        return lines.joined(separator: "\n")
    }

    private func skillToolRules(
        availableToolNames: [String],
        localeIdentifier: String
    ) -> String {
        let names = Set(availableToolNames)
        let isChinese = localeIdentifier.lowercased().hasPrefix("zh")
        if names.contains("skills_list"), names.contains("skills_read") {
            return isChinese
                ? "查询现有 skill 用 `skills_list`。相关 skill 只有索引、没有出现在“已加载正文”时，必须先用 `skills_read` 读取 `SKILL.md`，不要根据名称猜测细节。"
                : "Use `skills_list` to query installed skills. If a relevant skill appears only in the index, call `skills_read` before relying on its details."
        }
        return isChinese
            ? "Skills 在本轮是只读上下文。只依据“已加载正文”中实际出现的指令；不能读取未加载 skill，不要根据索引名称猜测细节。"
            : "Skills are read-only context for this turn. Follow only instructions present under Loaded skill bodies; you cannot read an unloaded skill, so never infer its details from index metadata."
    }

    private func memoryToolRules(
        availableToolNames: [String],
        localeIdentifier: String
    ) -> String {
        let names = Set(availableToolNames)
        let isChinese = localeIdentifier.lowercased().hasPrefix("zh")
        let canRead = names.contains("memory_search") || names.contains("memory_load")
        let canWriteDaily = names.contains("memory_write_daily")
        let canWriteLongTerm = names.contains("memory_upsert_longterm")
        var lines = [isChinese
            ? "- 已注入和检索的记忆只是辅助上下文；若与用户当前指令冲突，以当前指令为准。"
            : "- Injected and retrieved memory is supporting context. The user's current instruction wins on conflict."]
        if canRead {
            lines.append(isChinese
                ? "- 记忆正文不会自动注入。需要历史事实时使用 `memory_search` 或 `memory_load`；重复失败或执行环境敏感动作前，先检索 harness failure 经验。"
                : "- Memory bodies are not injected automatically. Use `memory_search` or `memory_load` for historical facts, and search harness failures before repeating a failed or environment-sensitive action.")
        }
        if canWriteDaily || canWriteLongTerm {
            var destinations: [String] = []
            if canWriteDaily { destinations.append("`memory_write_daily`") }
            if canWriteLongTerm { destinations.append("`memory_upsert_longterm`") }
            lines.append(isChinese
                ? "- 只在确有跨会话价值时用 \(destinations.joined(separator: " 或 ")) 保存客观、具体且去重的信息；写入成功前不得声称已记住。"
                : "- Only when information has real cross-session value, use \(destinations.joined(separator: " or ")) to save concrete, objective, deduplicated facts; never claim persistence before a successful result.")
        } else {
            lines.append(isChinese
                ? "- 本轮记忆只读；不能写入每日或长期记忆，也不得声称已记住。"
                : "- Memory is read-only for this turn. You cannot write daily or long-term memory and must not claim to have remembered anything persistently.")
        }
        return lines.joined(separator: "\n")
    }

    private func installedSkillIndex(_ skills: [AgentSkillIndexEntry]) -> String {
        guard !skills.isEmpty else { return "(none)" }
        return skills.map { skill in
            let description = skill.description
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let boundedDescription = description.count <= 200
                ? description
                : String(description.prefix(200)) + "…"
            let capabilities = skill.capabilities.isEmpty
                ? "metadata-only"
                : skill.capabilities.joined(separator: ",")
            return "- id=\(skill.id) | name=\(skill.name) | path=\(skill.skillFilePath) | capabilities=\(capabilities) | description=\(boundedDescription)"
        }.joined(separator: "\n")
    }

    private func emptyLoadedSkills(localeIdentifier: String) -> String {
        localeIdentifier.lowercased().hasPrefix("zh")
            ? "Skill 正文不自动注入；需要时用 `skills_read` 按需加载。"
            : "Skill bodies are not injected automatically; load one on demand with `skills_read`."
    }

    private func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func boundedSections(
        _ values: [String],
        totalUTF8ByteLimit: Int
    ) -> [String] {
        let byteLimit = max(0, totalUTF8ByteLimit)
        let byteCounts = values.map { $0.utf8.count }
        guard byteCounts.reduce(0, +) > byteLimit else { return values }

        var allocations = Array(repeating: 0, count: values.count)
        var remaining = byteLimit
        var active = Array(values.indices)

        while remaining > 0, !active.isEmpty {
            let share = max(1, remaining / active.count)
            var madeProgress = false
            for index in active where remaining > 0 {
                let needed = byteCounts[index] - allocations[index]
                guard needed > 0 else { continue }
                let grant = min(needed, share, remaining)
                allocations[index] += grant
                remaining -= grant
                madeProgress = true
            }
            active.removeAll { allocations[$0] >= byteCounts[$0] }
            if !madeProgress { break }
        }

        return zip(values, allocations).map { value, allocation in
            truncated(value, maximumUTF8Bytes: allocation)
        }
    }

    private func truncated(_ value: String, maximumUTF8Bytes: Int) -> String {
        let byteLimit = max(0, maximumUTF8Bytes)
        guard value.utf8.count > byteLimit else { return value }
        let marker = "\n…（已按模型上下文预算截断）"
        let available = max(0, byteLimit - marker.utf8.count)
        guard available > 0 else { return "…（已截断）" }

        var prefix = ""
        var usedBytes = 0
        for character in value {
            let characterBytes = String(character).utf8.count
            guard usedBytes + characterBytes <= available else { break }
            prefix.append(character)
            usedBytes += characterBytes
        }
        return prefix + marker
    }

    private func localDateString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private func weekdayString(
        _ date: Date,
        timeZone: TimeZone,
        localeIdentifier: String
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let index = calendar.component(.weekday, from: date) - 1
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        guard formatter.weekdaySymbols.indices.contains(index) else { return "" }
        return formatter.weekdaySymbols[index]
    }
}
