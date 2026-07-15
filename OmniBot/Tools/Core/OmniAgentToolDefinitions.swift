import Foundation

nonisolated enum OmniAgentToolDefinitions {
    static let all: [AgentToolDefinition] = [
        terminalExecute,
        terminalSessionStart,
        terminalSessionExec,
        terminalSessionRead,
        terminalSessionStop,
        fileRead,
        fileWrite,
        fileEdit,
        fileList,
        fileSearch,
        fileStat,
        fileMove,
        memorySearch,
        memoryLoad,
        memoryWriteDaily,
        memoryUpsertLongTerm,
        skillsList,
        skillsRead,
        browserUse,
        healthKitDataTypes,
        healthKitRequestAccess,
        healthKitQuantitySamples,
        healthKitQuantityStatistics,
        healthKitCategorySamples,
        healthKitWorkoutList,
        alarmReminderCreate,
        alarmReminderList,
        alarmReminderDelete,
        calendarList,
        calendarEventCreate,
        calendarEventList,
        calendarEventUpdate,
        calendarEventDelete,
        contactsSearch,
        contactsCreate,
        contactsUpdate,
        contactsDelete,
    ]

    private static let toolTitle = AgentValue.object([
        "type": .string("string"),
        "description": .string("A short, user-visible title describing this tool action."),
        "minLength": .number(1),
        "maxLength": .number(160),
    ])

    private static let path = AgentValue.object([
        "type": .string("string"),
        "description": .string("A workspace-relative path or an absolute /workspace/... path."),
    ])

    private static let environment = AgentValue.object([
        "type": .string("object"),
        "description": .string("Environment variables to persist or pass to the command."),
        "maxProperties": .number(128),
        "additionalProperties": .object([
            "type": .string("string"),
            "maxLength": .number(32 * 1_024),
        ]),
    ])

    private static let terminalExecute = definition(
        name: "terminal_execute",
        description: "Execute one non-interactive command in the local Alpine environment.",
        properties: [
            "tool_title": toolTitle,
            "command": .object([
                "type": .string("string"),
                "description": .string("Shell command to execute."),
                "maxLength": .number(64 * 1_024),
            ]),
            "working_directory": .object([
                "type": .string("string"),
                "description": .string("Guest working directory. Defaults to /workspace."),
            ]),
            "environment": environment,
            "timeout_seconds": integerSchema(
                description: "Timeout in seconds. Defaults to 120.",
                minimum: 1,
                maximum: 600
            ),
        ],
        required: ["tool_title", "command"]
    )

    private static let terminalSessionStart = definition(
        name: "terminal_session_start",
        description: "Create a logical terminal session that preserves cwd, environment, and its last output.",
        properties: [
            "tool_title": toolTitle,
            "working_directory": .object([
                "type": .string("string"),
                "description": .string("Initial guest working directory. Defaults to /workspace."),
            ]),
            "environment": environment,
        ],
        required: ["tool_title"]
    )

    private static let terminalSessionExec = definition(
        name: "terminal_session_exec",
        description: "Execute a command in a logical terminal session and update its cwd using a protected PWD sentinel.",
        properties: [
            "tool_title": toolTitle,
            "session_id": .object([
                "type": .string("string"),
                "description": .string("Session UUID returned by terminal_session_start."),
            ]),
            "command": .object([
                "type": .string("string"),
                "description": .string("Shell command to execute."),
                "maxLength": .number(64 * 1_024),
            ]),
            "environment": environment,
            "timeout_seconds": integerSchema(
                description: "Timeout in seconds. Defaults to 120.",
                minimum: 1,
                maximum: 600
            ),
        ],
        required: ["tool_title", "session_id", "command"]
    )

    private static let terminalSessionRead = definition(
        name: "terminal_session_read",
        description: "Read the last bounded output stored for a logical terminal session.",
        properties: [
            "tool_title": toolTitle,
            "session_id": .object(["type": .string("string")]),
            "offset_chars": integerSchema(
                description: "Character offset into the last output. Defaults to 0.",
                minimum: 0,
                maximum: 10_000_000
            ),
            "max_chars": integerSchema(
                description: "Maximum characters to return. Defaults to 32768.",
                minimum: 1,
                maximum: 131_072
            ),
        ],
        required: ["tool_title", "session_id"]
    )

    private static let terminalSessionStop = definition(
        name: "terminal_session_stop",
        description: "Stop any active command and remove a logical terminal session.",
        properties: [
            "tool_title": toolTitle,
            "session_id": .object(["type": .string("string")]),
        ],
        required: ["tool_title", "session_id"]
    )

    private static let fileRead = definition(
        name: "file_read",
        description: "Read a bounded UTF-8 or base64-encoded file from the workspace.",
        properties: [
            "tool_title": toolTitle,
            "path": path,
            "offset_bytes": integerSchema(
                description: "Byte offset. Defaults to 0.",
                minimum: 0,
                maximum: 2_147_483_647
            ),
            "max_bytes": integerSchema(
                description: "Maximum bytes to return.",
                minimum: 1,
                maximum: 2_097_152
            ),
            "encoding": .object([
                "type": .string("string"),
                "enum": .array([.string("utf8"), .string("base64")]),
            ]),
        ],
        required: ["tool_title", "path"]
    )

    private static let fileWrite = definition(
        name: "file_write",
        description: "Write or append bounded UTF-8 content to a workspace file.",
        properties: [
            "tool_title": toolTitle,
            "path": path,
            "content": .object(["type": .string("string")]),
            "mode": .object([
                "type": .string("string"),
                "enum": .array([.string("overwrite"), .string("append")]),
            ]),
            "create_parent_directories": .object(["type": .string("boolean")]),
        ],
        required: ["tool_title", "path", "content"]
    )

    private static let fileEdit = definition(
        name: "file_edit",
        description: "Replace an exact text fragment in a bounded UTF-8 workspace file.",
        properties: [
            "tool_title": toolTitle,
            "path": path,
            "old_text": .object(["type": .string("string")]),
            "new_text": .object(["type": .string("string")]),
            "replace_all": .object(["type": .string("boolean")]),
        ],
        required: ["tool_title", "path", "old_text", "new_text"]
    )

    private static let fileList = definition(
        name: "file_list",
        description: "List bounded file metadata beneath a workspace directory.",
        properties: [
            "tool_title": toolTitle,
            "path": path,
            "recursive": .object(["type": .string("boolean")]),
            "max_entries": integerSchema(
                description: "Maximum entries to return.",
                minimum: 1,
                maximum: 500
            ),
        ],
        required: ["tool_title"]
    )

    private static let fileSearch = definition(
        name: "file_search",
        description: "Search bounded UTF-8 workspace files and return matching lines.",
        properties: [
            "tool_title": toolTitle,
            "path": path,
            "query": .object(["type": .string("string")]),
            "case_sensitive": .object(["type": .string("boolean")]),
            "max_results": integerSchema(
                description: "Maximum matching lines to return.",
                minimum: 1,
                maximum: 200
            ),
        ],
        required: ["tool_title", "query"]
    )

    private static let fileStat = definition(
        name: "file_stat",
        description: "Return metadata for a file or directory inside the workspace.",
        properties: [
            "tool_title": toolTitle,
            "path": path,
        ],
        required: ["tool_title", "path"]
    )

    private static let fileMove = definition(
        name: "file_move",
        description: "Move a file or directory within the workspace.",
        properties: [
            "tool_title": toolTitle,
            "source": path,
            "destination": path,
            "overwrite": .object(["type": .string("boolean")]),
        ],
        required: ["tool_title", "source", "destination"]
    )

    private static let memorySearch = definition(
        name: "memory_search",
        description: "Lexically search long-term and daily Markdown memories.",
        properties: [
            "tool_title": toolTitle,
            "query": .object(["type": .string("string")]),
            "limit": integerSchema(
                description: "Maximum hits to return.",
                minimum: 1,
                maximum: 50
            ),
        ],
        required: ["tool_title", "query"]
    )

    private static let memoryLoad = definition(
        name: "memory_load",
        description: "Load long-term memory, daily memory, or both from the Markdown memory store.",
        properties: [
            "tool_title": toolTitle,
            "scope": .object([
                "type": .string("string"),
                "enum": .array([.string("all"), .string("longterm"), .string("daily")]),
            ]),
            "date": .object([
                "type": .string("string"),
                "description": .string("Optional ISO-8601 timestamp or yyyy-MM-dd date for daily memory."),
            ]),
        ],
        required: ["tool_title"]
    )

    private static let memoryWriteDaily = definition(
        name: "memory_write_daily",
        description: "Append a deduplicated entry to a daily Markdown memory file.",
        properties: [
            "tool_title": toolTitle,
            "text": .object(["type": .string("string")]),
            "date": .object([
                "type": .string("string"),
                "description": .string("Optional ISO-8601 timestamp or yyyy-MM-dd date."),
            ]),
        ],
        required: ["tool_title", "text"]
    )

    private static let memoryUpsertLongTerm = definition(
        name: "memory_upsert_longterm",
        description: "Append a deduplicated entry to long-term Markdown memory.",
        properties: [
            "tool_title": toolTitle,
            "text": .object(["type": .string("string")]),
        ],
        required: ["tool_title", "text"]
    )

    private static let skillsList = definition(
        name: "skills_list",
        description: "List the installed Apple-compatible skills index, including ids, paths, descriptions, and capability directories.",
        properties: [
            "tool_title": toolTitle,
            "query": .object([
                "type": .string("string"),
                "description": .string("Optional keyword matching skill id, name, description, or path."),
            ]),
            "limit": integerSchema(
                description: "Maximum results. Defaults to 50.",
                minimum: 1,
                maximum: 200
            ),
        ],
        required: ["tool_title"]
    )

    private static let skillsRead = definition(
        name: "skills_read",
        description: "Read an installed skill's SKILL.md body and its scripts, references, and assets paths.",
        properties: [
            "tool_title": toolTitle,
            "skillId": .object([
                "type": .string("string"),
                "description": .string("Skill id, name, SKILL.md path, or skill root path."),
            ]),
            "maxChars": integerSchema(
                description: "Maximum body characters. Defaults to 16000.",
                minimum: 512,
                maximum: 64_000
            ),
        ],
        required: ["tool_title", "skillId"]
    )

    private static let browserUse = definition(
        name: "browser_use",
        description: "Control a bounded WebKit.WebPage browser session shared with the chat's visible browser card. It uses Safari's WebKit engine, not the Safari app or Safari's cookie store. Website data is non-persistent and resets when the conversation changes. DOM click/type/hover/key actions are synthetic and are reported as untrusted emulation. get_cookies returns at most 200 redacted metadata entries. fetch saves at most 24 MiB beneath the workspace browser directory and returns an omnibot://browser artifact. Perform one action per call. When riskChallengeDetected is true, stop automation and ask the user to complete verification manually in the same session's browser card before continuing.",
        properties: [
            "tool_title": toolTitle,
            "action": .object([
                "type": .string("string"),
                "enum": .array([
                    "navigate", "screenshot", "click", "type", "get_text", "scroll",
                    "get_page_info", "execute_js", "find_elements", "hover",
                    "get_readable", "set_user_agent", "get_backbone", "fetch",
                    "new_tab", "close_tab", "list_tabs", "get_cookies",
                    "scroll_and_collect", "go_back", "go_forward", "press_key",
                    "wait_for_selector",
                ].map(AgentValue.string)),
            ]),
            "url": .object(["type": .string("string")]),
            "selector": .object(["type": .string("string")]),
            "text": .object(["type": .string("string")]),
            "script": .object(["type": .string("string")]),
            "coordinate_x": integerSchema(description: "Optional viewport X coordinate for click, type, or hover; provide both coordinates when using them instead of selector.", minimum: 0, maximum: 100_000),
            "coordinate_y": integerSchema(description: "Optional viewport Y coordinate for click, type, or hover; provide both coordinates when using them instead of selector.", minimum: 0, maximum: 100_000),
            "amount": integerSchema(description: "Scroll amount in pixels. Defaults to 500.", minimum: 1, maximum: 100_000),
            "direction": .object([
                "type": .string("string"),
                "enum": .array([.string("up"), .string("down")]),
            ]),
            "tab_id": integerSchema(description: "Monotonic target tab id. At most three tabs may exist simultaneously, but ids are not reused.", minimum: 1, maximum: 2_147_483_647),
            "item_selector": .object(["type": .string("string")]),
            "scroll_count": integerSchema(description: "Scroll collection count.", minimum: 1, maximum: 20),
            "max_depth": integerSchema(description: "DOM backbone depth.", minimum: 1, maximum: 12),
            "user_agent": .object([
                "type": .string("string"),
                "enum": .array([.string("desktop_safari"), .string("mobile_safari")]),
            ]),
            "keywords": .object([
                "type": .string("string"),
                "description": .string("Space-separated cookie-name keywords for get_cookies. With fuzzy=true, the name must contain every keyword; with fuzzy=false, it must exactly equal any keyword."),
            ]),
            "fuzzy": .object([
                "type": .string("boolean"),
                "description": .string("Cookie-name matching mode for get_cookies. Defaults to true."),
            ]),
            "read_image": .object(["type": .string("boolean")]),
            "key": .object(["type": .string("string")]),
            "timeout_ms": integerSchema(description: "Navigation, fetch, or selector-wait timeout in milliseconds. Defaults to 15000 for navigation and 5000 for selector waits.", minimum: 500, maximum: 30_000),
        ],
        required: ["tool_title", "action"]
    )

    private static let healthKitQuantityType = AgentValue.object([
        "type": .string("string"),
        "enum": .array([
            "step_count",
            "distance_walking_running",
            "distance_cycling",
            "distance_swimming",
            "active_energy_burned",
            "basal_energy_burned",
            "apple_exercise_time",
            "heart_rate",
            "resting_heart_rate",
            "walking_heart_rate_average",
            "heart_rate_variability_sdnn",
            "respiratory_rate",
            "oxygen_saturation",
            "body_mass",
            "height",
            "body_mass_index",
            "body_temperature",
            "blood_glucose",
            "blood_pressure_systolic",
            "blood_pressure_diastolic",
        ].map(AgentValue.string)),
    ])

    private static let healthKitCategoryType = AgentValue.object([
        "type": .string("string"),
        "enum": .array([
            .string("sleep_analysis"),
            .string("mindful_session"),
            .string("apple_stand_hour"),
        ]),
    ])

    private static let healthKitDataTypes = definition(
        name: "healthkit_data_types",
        description: "List the read-only HealthKit quantity, category, and workout data supported by this agent. This capability-only call does not request authorization or read health data.",
        properties: ["tool_title": toolTitle],
        required: ["tool_title"]
    )

    private static let healthKitRequestAccess = definition(
        name: "healthkit_request_access",
        description: "Start an incremental read-only HealthKit authorization request for selected types. Use only after the user's current request explicitly asks to access those health data types. If the result reports authorizationPending=true, stop the tool loop and ask the user to finish the system sheet; query only after a later user message. HealthKit does not reveal which read permissions the user granted.",
        properties: [
            "tool_title": toolTitle,
            "quantityTypes": .object([
                "type": .string("array"),
                "items": healthKitQuantityType,
                "maxItems": .number(20),
                "uniqueItems": .bool(true),
            ]),
            "categoryTypes": .object([
                "type": .string("array"),
                "items": healthKitCategoryType,
                "maxItems": .number(3),
                "uniqueItems": .bool(true),
            ]),
            "includeWorkouts": .object(["type": .string("boolean")]),
        ],
        required: ["tool_title"]
    )

    private static let healthKitQuantitySamples = definition(
        name: "healthkit_quantity_samples",
        description: "Read bounded raw samples for one HealthKit quantity type. Use only for an explicit current-turn user request because returned health data enters the configured model's context. This query never presents authorization UI; on authorization_required, call healthkit_request_access and wait for a later user message. An empty result can mean no matching data or no read permission.",
        properties: [
            "tool_title": toolTitle,
            "quantityType": healthKitQuantityType,
            "startAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range start. Defaults to one day before endAt."),
            ]),
            "endAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range end. Defaults to now."),
            ]),
            "limit": integerSchema(
                description: "Maximum samples. Defaults to 100.",
                minimum: 1,
                maximum: 200
            ),
        ],
        required: ["tool_title", "quantityType"]
    )

    private static let healthKitQuantityStatistics = definition(
        name: "healthkit_quantity_statistics",
        description: "Calculate a HealthKit quantity statistic over a bounded range. Use sum for cumulative types and average, minimum, or maximum for discrete types. This query never presents authorization UI; on authorization_required, call healthkit_request_access and wait for a later user message. Use only for an explicit current-turn user request because returned health data enters the configured model's context.",
        properties: [
            "tool_title": toolTitle,
            "quantityType": healthKitQuantityType,
            "statistic": .object([
                "type": .string("string"),
                "enum": .array([
                    .string("sum"),
                    .string("average"),
                    .string("minimum"),
                    .string("maximum"),
                ]),
            ]),
            "startAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range start. Defaults to one day before endAt."),
            ]),
            "endAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range end. Defaults to now."),
            ]),
        ],
        required: ["tool_title", "quantityType", "statistic"]
    )

    private static let healthKitCategorySamples = definition(
        name: "healthkit_category_samples",
        description: "Read bounded HealthKit category samples such as sleep stages, mindful sessions, or stand hours. This query never presents authorization UI; on authorization_required, call healthkit_request_access and wait for a later user message. Use only for an explicit current-turn user request because returned health data enters the configured model's context. An empty result can mean no matching data or no read permission.",
        properties: [
            "tool_title": toolTitle,
            "categoryType": healthKitCategoryType,
            "startAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range start. Defaults to seven days before endAt."),
            ]),
            "endAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range end. Defaults to now."),
            ]),
            "limit": integerSchema(
                description: "Maximum samples. Defaults to 100.",
                minimum: 1,
                maximum: 200
            ),
        ],
        required: ["tool_title", "categoryType"]
    )

    private static let healthKitWorkoutList = definition(
        name: "healthkit_workout_list",
        description: "List bounded HealthKit workouts with duration and available energy or distance statistics. This query never presents authorization UI; on authorization_required, call healthkit_request_access and wait for a later user message. Use only for an explicit current-turn user request because returned health data enters the configured model's context. An empty result can mean no matching data or no read permission.",
        properties: [
            "tool_title": toolTitle,
            "startAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range start. Defaults to 30 days before endAt."),
            ]),
            "endAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 range end. Defaults to now."),
            ]),
            "limit": integerSchema(
                description: "Maximum workouts. Defaults to 50.",
                minimum: 1,
                maximum: 100
            ),
        ],
        required: ["tool_title"]
    )

    private static let alarmReminderCreate = definition(
        name: "alarm_reminder_create",
        description: "Create an OmniBot-managed alarm. exact_alarm uses AlarmKit on iOS; on macOS it degrades to a local notification. clock_app is unsupported.",
        properties: [
            "tool_title": toolTitle,
            "mode": .object([
                "type": .string("string"),
                "enum": .array([.string("exact_alarm"), .string("clock_app")]),
                "description": .string("exact_alarm uses AlarmKit on iOS and UserNotifications on macOS. clock_app returns a structured unsupported-mode error."),
            ]),
            "title": .object(["type": .string("string")]),
            "triggerAt": .object([
                "type": .string("string"),
                "description": .string("ISO-8601 trigger time including an offset when possible."),
            ]),
            "message": .object(["type": .string("string")]),
            "timezone": .object(["type": .string("string")]),
            "allowWhileIdle": .object(["type": .string("boolean")]),
            "skipUi": .object(["type": .string("boolean")]),
        ],
        required: ["tool_title", "mode", "title", "triggerAt"]
    )

    private static let alarmReminderList = definition(
        name: "alarm_reminder_list",
        description: "List active OmniBot-managed AlarmKit alarms on iOS or degraded notification reminders on macOS.",
        properties: ["tool_title": toolTitle],
        required: ["tool_title"]
    )

    private static let alarmReminderDelete = definition(
        name: "alarm_reminder_delete",
        description: "Delete an OmniBot-managed AlarmKit alarm or degraded macOS notification reminder by alarmId.",
        properties: [
            "tool_title": toolTitle,
            "alarmId": .object(["type": .string("string")]),
        ],
        required: ["tool_title", "alarmId"]
    )

    private static let calendarList = definition(
        name: "calendar_list",
        description: "List Apple system calendars after requesting full calendar access. writableOnly defaults to true. visibleOnly is accepted for Android compatibility, but EventKit cannot expose Calendar app visibility and reports visibleFilterApplied=false.",
        properties: [
            "tool_title": toolTitle,
            "writableOnly": .object(["type": .string("boolean")]),
            "visibleOnly": .object(["type": .string("boolean")]),
        ],
        required: ["tool_title"]
    )

    private static let reminderMinutes = AgentValue.object([
        "type": .string("array"),
        "items": .object([
            "type": .string("integer"),
            "minimum": .number(0),
            "maximum": .number(525_600),
        ]),
        "maxItems": .number(16),
    ])

    private static let calendarEventCreate = definition(
        name: "calendar_event_create",
        description: "Create an event in Apple Calendar using ISO-8601 start and end times.",
        properties: [
            "tool_title": toolTitle,
            "title": .object(["type": .string("string")]),
            "startAt": .object(["type": .string("string")]),
            "endAt": .object(["type": .string("string")]),
            "calendarId": .object(["type": .string("string")]),
            "description": .object(["type": .string("string")]),
            "location": .object(["type": .string("string")]),
            "timezone": .object(["type": .string("string")]),
            "allDay": .object(["type": .string("boolean")]),
            "reminderMinutes": reminderMinutes,
        ],
        required: ["tool_title", "title", "startAt", "endAt"]
    )

    private static let calendarEventList = definition(
        name: "calendar_event_list",
        description: "Query Apple Calendar events by time range, keyword, and optional calendarId.",
        properties: [
            "tool_title": toolTitle,
            "calendarId": .object(["type": .string("string")]),
            "startAt": .object(["type": .string("string")]),
            "endAt": .object(["type": .string("string")]),
            "query": .object(["type": .string("string")]),
            "limit": integerSchema(description: "Maximum results. Defaults to 50.", minimum: 1, maximum: 200),
        ],
        required: ["tool_title"]
    )

    private static let calendarEventUpdate = definition(
        name: "calendar_event_update",
        description: "Update an Apple Calendar event by eventId. Only supplied fields are changed.",
        properties: [
            "tool_title": toolTitle,
            "eventId": .object(["type": .string("string")]),
            "title": .object(["type": .string("string")]),
            "startAt": .object(["type": .string("string")]),
            "endAt": .object(["type": .string("string")]),
            "description": .object(["type": .string("string")]),
            "location": .object(["type": .string("string")]),
            "timezone": .object(["type": .string("string")]),
            "allDay": .object(["type": .string("boolean")]),
            "reminderMinutes": reminderMinutes,
        ],
        required: ["tool_title", "eventId"]
    )

    private static let calendarEventDelete = definition(
        name: "calendar_event_delete",
        description: "Delete an Apple Calendar event by eventId.",
        properties: [
            "tool_title": toolTitle,
            "eventId": .object(["type": .string("string")]),
        ],
        required: ["tool_title", "eventId"]
    )

    private static let contactLabeledValues = AgentValue.object([
        "type": .string("array"),
        "items": .object([
            "type": .string("object"),
            "properties": .object([
                "label": .object([
                    "type": .string("string"),
                    "description": .string("Examples: home, work, mobile, iphone, main, other."),
                ]),
                "value": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("label"), .string("value")]),
            "additionalProperties": .bool(false),
        ]),
        "maxItems": .number(32),
    ])

    private static let contactsSearch = definition(
        name: "contacts_search",
        description: "Search the Apple address book by name, organization, phone, or email.",
        properties: [
            "tool_title": toolTitle,
            "query": .object(["type": .string("string")]),
            "limit": integerSchema(description: "Maximum results. Defaults to 25.", minimum: 1, maximum: 100),
        ],
        required: ["tool_title", "query"]
    )

    private static let contactsCreate = definition(
        name: "contacts_create",
        description: "Create a contact in the Apple address book.",
        properties: [
            "tool_title": toolTitle,
            "givenName": .object(["type": .string("string")]),
            "familyName": .object(["type": .string("string")]),
            "organization": .object(["type": .string("string")]),
            "phones": contactLabeledValues,
            "emails": contactLabeledValues,
        ],
        required: ["tool_title"]
    )

    private static let contactsUpdate = definition(
        name: "contacts_update",
        description: "Update an Apple address-book contact by contactId. Only supplied fields are changed.",
        properties: [
            "tool_title": toolTitle,
            "contactId": .object(["type": .string("string")]),
            "givenName": .object(["type": .string("string")]),
            "familyName": .object(["type": .string("string")]),
            "organization": .object(["type": .string("string")]),
            "phones": contactLabeledValues,
            "emails": contactLabeledValues,
        ],
        required: ["tool_title", "contactId"]
    )

    private static let contactsDelete = definition(
        name: "contacts_delete",
        description: "Delete an Apple address-book contact by contactId.",
        properties: [
            "tool_title": toolTitle,
            "contactId": .object(["type": .string("string")]),
        ],
        required: ["tool_title", "contactId"]
    )

    private static func definition(
        name: String,
        description: String,
        properties: [String: AgentValue],
        required: [String]
    ) -> AgentToolDefinition {
        AgentToolDefinition(
            name: name,
            description: description,
            parameters: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(AgentValue.string)),
                "additionalProperties": .bool(false),
            ])
        )
    }

    private static func integerSchema(
        description: String,
        minimum: Int,
        maximum: Int
    ) -> AgentValue {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .number(Double(minimum)),
            "maximum": .number(Double(maximum)),
        ])
    }
}
