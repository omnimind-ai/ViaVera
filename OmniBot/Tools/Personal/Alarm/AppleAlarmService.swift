import Foundation

#if os(iOS)
import AlarmKit
import SwiftUI
#elseif os(macOS)
import UserNotifications
#endif

@MainActor
final class AppleAlarmService {
    #if os(macOS)
    private static let notificationIdentifierPrefix = "omnibot.alarm."

    private let notificationCenter: UNUserNotificationCenter
    private let foregroundNotificationDelegate: AppleUserNotificationCenterDelegate
    #endif

    private let recordStore: AppleAlarmRecordStore

    #if os(macOS)
    init(
        recordFileURL: URL,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        recordStore = AppleAlarmRecordStore(fileURL: recordFileURL)
        self.notificationCenter = notificationCenter
        foregroundNotificationDelegate = AppleUserNotificationCenterDelegate()
        notificationCenter.delegate = foregroundNotificationDelegate
    }

    var isForegroundNotificationPresentationInstalled: Bool {
        notificationCenter.delegate === foregroundNotificationDelegate
    }
    #else
    init(recordFileURL: URL) {
        recordStore = AppleAlarmRecordStore(fileURL: recordFileURL)
    }
    #endif

    func create(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let mode = try arguments.requiredString("mode", maximumLength: 32)
        guard mode == "exact_alarm" else {
            throw ApplePersonalToolError(
                "Mode 'clock_app' is not supported on Apple platforms. Use 'exact_alarm'.",
                code: "unsupported_mode",
                backend: "none"
            )
        }

        let title = try arguments.requiredString("title", maximumLength: 160)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw OmniAgentToolError("Parameter 'title' must not be empty.")
        }
        let triggerAt = try ApplePersonalToolParsing.date(
            arguments.requiredString("triggerAt", maximumLength: 128),
            parameterName: "triggerAt"
        )
        guard triggerAt > Date.now else {
            throw OmniAgentToolError("Parameter 'triggerAt' must be in the future.")
        }
        let message = try arguments.optionalString("message", maximumLength: 1_024)
        let requestedTimeZone = try ApplePersonalToolParsing.optionalTimeZone(
            arguments.optionalString("timezone", maximumLength: 128)
        )
        let allowWhileIdle = try arguments.bool("allowWhileIdle", default: true)
        let skipUI = try arguments.bool("skipUi", default: true)

        #if os(iOS)
        try await ensureAlarmKitAuthorization()

        let identifier = UUID()
        let metadata = OmniBotAlarmMetadata(
            title: title,
            message: message,
            triggerAt: triggerAt,
            timeZoneIdentifier: requestedTimeZone?.identifier
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title)
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<OmniBotAlarmMetadata>.alarm(
            schedule: .fixed(triggerAt),
            attributes: attributes
        )
        let alarm = try await AlarmManager.shared.schedule(
            id: identifier,
            configuration: configuration
        )
        let record = OmniBotAlarmRecord(
            alarmID: alarm.id.uuidString,
            backend: "alarmkit",
            title: title,
            message: message,
            triggerAt: triggerAt,
            timeZoneIdentifier: requestedTimeZone?.identifier,
            exact: true,
            createdAt: .now
        )
        do {
            let activeAlarmIDs = Set(
                try AlarmManager.shared.alarms.map { $0.id.uuidString }
            )
            _ = try await recordStore.reconcile(activeAlarmIDs: activeAlarmIDs)
            try await recordStore.upsert(record)
        } catch {
            try? AlarmManager.shared.cancel(id: alarm.id)
            throw error
        }

        return AgentToolExecutionResult(
            content: "Exact iOS alarm scheduled with AlarmKit.",
            metadata: [
                "alarm": alarmValue(alarm),
                "record": record.agentValue,
                "backend": .string("alarmkit"),
                "exact": .bool(true),
                "title": .string(title),
                "message": message.map(AgentValue.string) ?? .null,
                "requestedTimezone": requestedTimeZone.map { .string($0.identifier) } ?? .null,
                "allowWhileIdleAccepted": .bool(allowWhileIdle),
                "skipUiAccepted": .bool(skipUI),
            ]
        )
        #elseif os(macOS)
        try await ensureNotificationAuthorization()

        let identifier = Self.notificationIdentifierPrefix + UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message ?? ""
        content.sound = .default

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = requestedTimeZone ?? .autoupdatingCurrent
        var dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: triggerAt
        )
        dateComponents.timeZone = calendar.timeZone
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: false
            )
        )
        try await notificationCenter.add(request)
        let record = OmniBotAlarmRecord(
            alarmID: identifier,
            backend: "user_notifications",
            title: title,
            message: message,
            triggerAt: triggerAt,
            timeZoneIdentifier: calendar.timeZone.identifier,
            exact: false,
            createdAt: .now
        )
        do {
            let activeAlarmIDs = Set(
                await notificationCenter
                    .pendingNotificationRequests()
                    .filter {
                        $0.identifier.hasPrefix(Self.notificationIdentifierPrefix)
                    }
                    .map(\.identifier)
            )
            _ = try await recordStore.reconcile(activeAlarmIDs: activeAlarmIDs)
            try await recordStore.upsert(record)
        } catch {
            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: [identifier]
            )
            throw error
        }

        return AgentToolExecutionResult(
            content: "macOS notification reminder scheduled. It is not a continuously ringing exact alarm.",
            metadata: [
                "alarmId": .string(identifier),
                "record": record.agentValue,
                "triggerAt": .string(ApplePersonalToolParsing.iso8601(triggerAt)),
                "backend": .string("user_notifications"),
                "exact": .bool(false),
                "degraded": .bool(true),
                "requestedTimezone": .string(calendar.timeZone.identifier),
                "allowWhileIdleAccepted": .bool(false),
                "skipUiAccepted": .bool(skipUI),
            ]
        )
        #endif
    }

    func list(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        _ = arguments

        #if os(iOS)
        try await ensureAlarmKitAuthorization()
        let alarms = try AlarmManager.shared.alarms
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let records = try await recordStore.reconcile(
            activeAlarmIDs: Set(alarms.map { $0.id.uuidString })
        )
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.alarmID, $0) }
        )
        return AgentToolExecutionResult(
            content: alarms.isEmpty
                ? "No OmniBot AlarmKit alarms are scheduled."
                : "Found \(alarms.count) OmniBot AlarmKit alarm(s).",
            metadata: [
                "alarms": .array(alarms.map {
                    mergedAlarmValue($0, record: recordsByID[$0.id.uuidString])
                }),
                "count": .number(Double(alarms.count)),
                "recordCount": .number(Double(records.count)),
                "backend": .string("alarmkit"),
                "exact": .bool(true),
            ]
        )
        #elseif os(macOS)
        try await ensureNotificationAuthorization()
        let requests = await notificationCenter
            .pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.notificationIdentifierPrefix) }
            .sorted { $0.identifier < $1.identifier }
        let records = try await recordStore.reconcile(
            activeAlarmIDs: Set(requests.map(\.identifier))
        )
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.alarmID, $0) }
        )
        let alarms = requests.map { request -> AgentValue in
            let triggerAt = (request.trigger as? UNCalendarNotificationTrigger)?
                .nextTriggerDate()
            var value = recordsByID[request.identifier]?.agentValue.objectValue ?? [:]
            value.merge([
                "alarmId": .string(request.identifier),
                "title": value["title"] ?? .string(request.content.title),
                "message": value["message"] ?? .string(request.content.body),
                "triggerAt": triggerAt.map {
                    .string(ApplePersonalToolParsing.iso8601($0))
                } ?? .null,
                "state": .string("scheduled"),
            ]) { _, new in new }
            return .object(value)
        }
        return AgentToolExecutionResult(
            content: alarms.isEmpty
                ? "No OmniBot macOS notification reminders are scheduled."
                : "Found \(alarms.count) OmniBot macOS notification reminder(s).",
            metadata: [
                "alarms": .array(alarms),
                "count": .number(Double(alarms.count)),
                "recordCount": .number(Double(records.count)),
                "backend": .string("user_notifications"),
                "exact": .bool(false),
                "degraded": .bool(true),
            ]
        )
        #endif
    }

    func delete(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let rawIdentifier = try arguments.requiredString("alarmId", maximumLength: 256)

        #if os(iOS)
        try await ensureAlarmKitAuthorization()
        guard let identifier = UUID(uuidString: rawIdentifier) else {
            throw OmniAgentToolError("Invalid parameter 'alarmId': expected an AlarmKit UUID.")
        }
        let alarms = try AlarmManager.shared.alarms
        guard alarms.contains(where: { $0.id == identifier }) else {
            throw ApplePersonalToolError(
                "No OmniBot AlarmKit alarm exists with id '\(rawIdentifier)'.",
                code: "not_found",
                backend: "alarmkit"
            )
        }
        try AlarmManager.shared.cancel(id: identifier)
        let recordRemoved = (try? await recordStore.remove(alarmID: rawIdentifier)) ?? false
        return AgentToolExecutionResult(
            content: "AlarmKit alarm deleted.",
            metadata: [
                "alarmId": .string(rawIdentifier),
                "deleted": .bool(true),
                "recordRemoved": .bool(recordRemoved),
                "backend": .string("alarmkit"),
            ]
        )
        #elseif os(macOS)
        try await ensureNotificationAuthorization()
        guard rawIdentifier.hasPrefix(Self.notificationIdentifierPrefix) else {
            throw OmniAgentToolError(
                "Invalid parameter 'alarmId': expected an OmniBot-managed notification id."
            )
        }
        let pending = await notificationCenter.pendingNotificationRequests()
        guard pending.contains(where: { $0.identifier == rawIdentifier }) else {
            throw ApplePersonalToolError(
                "No pending OmniBot notification reminder exists with id '\(rawIdentifier)'.",
                code: "not_found",
                backend: "user_notifications"
            )
        }
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [rawIdentifier]
        )
        let recordRemoved = (try? await recordStore.remove(alarmID: rawIdentifier)) ?? false
        return AgentToolExecutionResult(
            content: "macOS notification reminder deleted.",
            metadata: [
                "alarmId": .string(rawIdentifier),
                "deleted": .bool(true),
                "recordRemoved": .bool(recordRemoved),
                "backend": .string("user_notifications"),
                "degraded": .bool(true),
            ]
        )
        #endif
    }

    #if os(iOS)
    private func ensureAlarmKitAuthorization() async throws {
        let manager = AlarmManager.shared
        let state: AlarmManager.AuthorizationState
        if manager.authorizationState == .notDetermined {
            state = try await manager.requestAuthorization()
        } else {
            state = manager.authorizationState
        }

        guard state == .authorized else {
            throw ApplePersonalToolError(
                "Alarm permission is not authorized. Enable OmniBot alarms in Settings.",
                code: "permission_denied",
                permission: "alarms",
                authorizationStatus: alarmAuthorizationName(state),
                backend: "alarmkit",
                requiresSystemSettings: state == .denied
            )
        }
    }

    private func alarmAuthorizationName(
        _ state: AlarmManager.AuthorizationState
    ) -> String {
        switch state {
        case .notDetermined: "not_determined"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }

    private func alarmValue(_ alarm: Alarm) -> AgentValue {
        var result: [String: AgentValue] = [
            "alarmId": .string(alarm.id.uuidString),
            "state": .string(alarmStateName(alarm.state)),
        ]
        switch alarm.schedule {
        case let .fixed(date):
            result["schedule"] = .object([
                "kind": .string("fixed"),
                "triggerAt": .string(ApplePersonalToolParsing.iso8601(date)),
            ])
        case let .relative(relative):
            result["schedule"] = .object([
                "kind": .string("relative"),
                "hour": .number(Double(relative.time.hour)),
                "minute": .number(Double(relative.time.minute)),
            ])
        case nil:
            result["schedule"] = .null
        @unknown default:
            result["schedule"] = .object(["kind": .string("unknown")])
        }
        return .object(result)
    }

    private func mergedAlarmValue(
        _ alarm: Alarm,
        record: OmniBotAlarmRecord?
    ) -> AgentValue {
        var result = record?.agentValue.objectValue ?? [:]
        if case let .object(alarmFields) = alarmValue(alarm) {
            result.merge(alarmFields) { _, new in new }
        }
        return .object(result)
    }

    private func alarmStateName(_ state: Alarm.State) -> String {
        switch state {
        case .scheduled: "scheduled"
        case .countdown: "countdown"
        case .paused: "paused"
        case .alerting: "alerting"
        @unknown default: "unknown"
        }
    }
    #elseif os(macOS)
    private func ensureNotificationAuthorization() async throws {
        var status = await notificationCenter.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            status = await notificationCenter.notificationSettings().authorizationStatus
        }

        guard status == .authorized || status == .provisional else {
            throw ApplePersonalToolError(
                "Notification permission is not authorized. Enable notifications for OmniBot in System Settings.",
                code: "permission_denied",
                permission: "notifications",
                authorizationStatus: notificationAuthorizationName(status),
                backend: "user_notifications",
                requiresSystemSettings: status == .denied
            )
        }
    }

    private func notificationAuthorizationName(
        _ status: UNAuthorizationStatus
    ) -> String {
        switch status {
        case .notDetermined: "not_determined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
    #endif
}
