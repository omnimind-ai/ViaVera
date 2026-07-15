import EventKit
import Foundation

@MainActor
final class AppleCalendarService {
    static let maximumEventQueryYears = 10

    private let eventStore = EKEventStore()

    func listCalendars(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        try await ensureFullAccess()
        let writableOnly = try arguments.bool("writableOnly", default: true)
        let visibleOnly = try arguments.bool("visibleOnly", default: false)
        let calendars = eventStore.calendars(for: .event)
            .filter { !writableOnly || $0.allowsContentModifications }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

        return AgentToolExecutionResult(
            content: calendars.isEmpty
                ? "No matching Apple calendars were found."
                : "Found \(calendars.count) Apple calendar(s).",
            metadata: [
                "calendars": .array(calendars.map(calendarValue)),
                "count": .number(Double(calendars.count)),
                "writableOnly": .bool(writableOnly),
                "visibleOnlyRequested": .bool(visibleOnly),
                "visibleFilterApplied": .bool(false),
                "visibleFilterLimitation": visibleOnly
                    ? .string("EventKit does not expose Calendar app visibility state; all permission-visible calendars were considered.")
                    : .null,
                "backend": .string("eventkit"),
            ]
        )
    }

    func createEvent(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        try await ensureFullAccess()
        let title = try arguments.requiredString("title", maximumLength: 1_024)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw OmniAgentToolError("Parameter 'title' must not be empty.")
        }
        let startAt = try ApplePersonalToolParsing.date(
            arguments.requiredString("startAt", maximumLength: 128),
            parameterName: "startAt"
        )
        let endAt = try ApplePersonalToolParsing.date(
            arguments.requiredString("endAt", maximumLength: 128),
            parameterName: "endAt"
        )
        guard endAt > startAt else {
            throw OmniAgentToolError("Parameter 'endAt' must be later than 'startAt'.")
        }
        let calendar = try selectedCalendar(
            identifier: arguments.optionalString("calendarId", maximumLength: 512),
            requiresWriteAccess: true
        )
        let timeZone = try ApplePersonalToolParsing.optionalTimeZone(
            arguments.optionalString("timezone", maximumLength: 128)
        )
        let reminderMinutes = try ApplePersonalToolParsing.integerArray(
            arguments,
            name: "reminderMinutes",
            range: 0...525_600,
            maximumCount: 16
        ) ?? []

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startAt
        event.endDate = endAt
        event.notes = try arguments.optionalString("description", maximumLength: 32_768)
        event.location = try arguments.optionalString("location", maximumLength: 4_096)
        event.timeZone = timeZone
        event.isAllDay = try arguments.bool("allDay", default: false)
        replaceAlarms(on: event, reminderMinutes: reminderMinutes)

        try eventStore.save(event, span: .thisEvent, commit: true)
        guard event.eventIdentifier != nil else {
            throw ApplePersonalToolError(
                "EventKit saved the event but did not return an event identifier.",
                code: "missing_identifier",
                backend: "eventkit"
            )
        }

        return AgentToolExecutionResult(
            content: "Apple Calendar event created.",
            metadata: [
                "event": eventValue(event),
                "created": .bool(true),
                "backend": .string("eventkit"),
            ]
        )
    }

    func listEvents(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let defaultStart = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        let defaultEnd = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        let startAt: Date
        if let rawStart = try arguments.optionalString("startAt", maximumLength: 128) {
            startAt = try ApplePersonalToolParsing.date(rawStart, parameterName: "startAt")
        } else {
            startAt = defaultStart
        }
        let endAt: Date
        if let rawEnd = try arguments.optionalString("endAt", maximumLength: 128) {
            endAt = try ApplePersonalToolParsing.date(rawEnd, parameterName: "endAt")
        } else {
            endAt = defaultEnd
        }
        try Self.validateEventQueryRange(startAt: startAt, endAt: endAt)
        let query = try arguments.optionalString("query", maximumLength: 4_096)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = try arguments.integer("limit", default: 50, range: 1...200) ?? 50
        let calendarIdentifier = try arguments.optionalString(
            "calendarId",
            maximumLength: 512
        )

        try await ensureFullAccess()
        let calendars = try calendarIdentifier.map {
            [try selectedCalendar(identifier: $0, requiresWriteAccess: false)]
        }
        let predicate = eventStore.predicateForEvents(
            withStart: startAt,
            end: endAt,
            calendars: calendars
        )
        let events = eventStore.events(matching: predicate)
            .filter { event in
                guard let query, !query.isEmpty else { return true }
                return event.title.localizedStandardContains(query)
                    || (event.notes?.localizedStandardContains(query) ?? false)
                    || (event.location?.localizedStandardContains(query) ?? false)
                    || event.calendar.title.localizedStandardContains(query)
            }
            .sorted { $0.startDate < $1.startDate }
        let boundedEvents = Array(events.prefix(limit))

        return AgentToolExecutionResult(
            content: boundedEvents.isEmpty
                ? "No matching Apple Calendar events were found."
                : "Found \(boundedEvents.count) Apple Calendar event(s).",
            metadata: [
                "events": .array(boundedEvents.map(eventValue)),
                "count": .number(Double(boundedEvents.count)),
                "truncated": .bool(events.count > boundedEvents.count),
                "rangeStart": .string(ApplePersonalToolParsing.iso8601(startAt)),
                "rangeEnd": .string(ApplePersonalToolParsing.iso8601(endAt)),
                "backend": .string("eventkit"),
            ]
        )
    }

    static func validateEventQueryRange(startAt: Date, endAt: Date) throws {
        guard endAt > startAt else {
            throw OmniAgentToolError("Parameter 'endAt' must be later than 'startAt'.")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let maximumEnd = calendar.date(
            byAdding: .year,
            value: maximumEventQueryYears,
            to: startAt
        ), endAt <= maximumEnd else {
            throw ApplePersonalToolError(
                "Calendar event queries may span at most "
                    + "\(maximumEventQueryYears) years. Split the request into smaller date ranges.",
                code: "range_too_large",
                backend: "eventkit",
                guidance: "Split the calendar query into ranges of no more than \(maximumEventQueryYears) years."
            )
        }
    }

    func updateEvent(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        try await ensureFullAccess()
        let identifier = try arguments.requiredString("eventId", maximumLength: 512)
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw ApplePersonalToolError(
                "No Apple Calendar event exists with id '\(identifier)'.",
                code: "not_found",
                backend: "eventkit"
            )
        }
        guard event.calendar.allowsContentModifications else {
            throw ApplePersonalToolError(
                "The selected event belongs to a read-only calendar.",
                code: "read_only",
                backend: "eventkit"
            )
        }

        if arguments.values["title"] != nil {
            let title = try arguments.requiredString("title", maximumLength: 1_024)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw OmniAgentToolError("Parameter 'title' must not be empty.")
            }
            event.title = title
        }
        if let rawStart = try arguments.optionalString("startAt", maximumLength: 128) {
            event.startDate = try ApplePersonalToolParsing.date(
                rawStart,
                parameterName: "startAt"
            )
        }
        if let rawEnd = try arguments.optionalString("endAt", maximumLength: 128) {
            event.endDate = try ApplePersonalToolParsing.date(
                rawEnd,
                parameterName: "endAt"
            )
        }
        guard event.endDate > event.startDate else {
            throw OmniAgentToolError("The updated event end must be later than its start.")
        }
        if arguments.values["description"] != nil {
            event.notes = try arguments.optionalString("description", maximumLength: 32_768)
        }
        if arguments.values["location"] != nil {
            event.location = try arguments.optionalString("location", maximumLength: 4_096)
        }
        if arguments.values["timezone"] != nil {
            event.timeZone = try ApplePersonalToolParsing.optionalTimeZone(
                arguments.optionalString("timezone", maximumLength: 128)
            )
        }
        if arguments.values["allDay"] != nil {
            event.isAllDay = try arguments.bool("allDay", default: event.isAllDay)
        }
        if let reminderMinutes = try ApplePersonalToolParsing.integerArray(
            arguments,
            name: "reminderMinutes",
            range: 0...525_600,
            maximumCount: 16
        ) {
            replaceAlarms(on: event, reminderMinutes: reminderMinutes)
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        return AgentToolExecutionResult(
            content: "Apple Calendar event updated.",
            metadata: [
                "event": eventValue(event),
                "updated": .bool(true),
                "backend": .string("eventkit"),
            ]
        )
    }

    func deleteEvent(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        try await ensureFullAccess()
        let identifier = try arguments.requiredString("eventId", maximumLength: 512)
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw ApplePersonalToolError(
                "No Apple Calendar event exists with id '\(identifier)'.",
                code: "not_found",
                backend: "eventkit"
            )
        }
        guard event.calendar.allowsContentModifications else {
            throw ApplePersonalToolError(
                "The selected event belongs to a read-only calendar.",
                code: "read_only",
                backend: "eventkit"
            )
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
        return AgentToolExecutionResult(
            content: "Apple Calendar event deleted.",
            metadata: [
                "eventId": .string(identifier),
                "deleted": .bool(true),
                "backend": .string("eventkit"),
            ]
        )
    }

    private func ensureFullAccess() async throws {
        var status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            _ = try await eventStore.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
        }
        guard status == .fullAccess else {
            throw ApplePersonalToolError(
                "Full calendar access is not authorized. Enable Calendars access for OmniBot in Settings.",
                code: "permission_denied",
                permission: "calendars",
                authorizationStatus: authorizationName(status),
                backend: "eventkit",
                requiresSystemSettings: status == .denied || status == .restricted || status == .writeOnly
            )
        }
    }

    private func authorizationName(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not_determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .fullAccess: "full_access"
        case .writeOnly: "write_only"
        @unknown default: "unknown"
        }
    }

    private func selectedCalendar(
        identifier: String?,
        requiresWriteAccess: Bool
    ) throws -> EKCalendar {
        let calendar: EKCalendar?
        if let identifier {
            calendar = eventStore.calendar(withIdentifier: identifier)
        } else {
            calendar = eventStore.defaultCalendarForNewEvents
        }
        guard let calendar else {
            throw ApplePersonalToolError(
                identifier == nil
                    ? "No default Apple Calendar is configured for new events."
                    : "No Apple Calendar exists with id '\(identifier ?? "")'.",
                code: "not_found",
                backend: "eventkit"
            )
        }
        if requiresWriteAccess, !calendar.allowsContentModifications {
            throw ApplePersonalToolError(
                "Calendar '\(calendar.title)' is read-only.",
                code: "read_only",
                backend: "eventkit"
            )
        }
        return calendar
    }

    private func replaceAlarms(on event: EKEvent, reminderMinutes: [Int]) {
        for alarm in event.alarms ?? [] {
            event.removeAlarm(alarm)
        }
        for minutes in reminderMinutes {
            event.addAlarm(EKAlarm(relativeOffset: -Double(minutes * 60)))
        }
    }

    private func calendarValue(_ calendar: EKCalendar) -> AgentValue {
        .object([
            "calendarId": .string(calendar.calendarIdentifier),
            "title": .string(calendar.title),
            "type": .string(calendarTypeName(calendar.type)),
            "source": .string(calendar.source.title),
            "allowsContentModifications": .bool(calendar.allowsContentModifications),
            "isSubscribed": .bool(calendar.isSubscribed),
            "isImmutable": .bool(calendar.isImmutable),
        ])
    }

    private func eventValue(_ event: EKEvent) -> AgentValue {
        let alarms = (event.alarms ?? []).compactMap { alarm -> AgentValue? in
            guard alarm.relativeOffset <= 0 else { return nil }
            return .number((-alarm.relativeOffset / 60).rounded())
        }
        return .object([
            "eventId": event.eventIdentifier.map(AgentValue.string) ?? .null,
            "title": .string(event.title),
            "startAt": .string(ApplePersonalToolParsing.iso8601(event.startDate)),
            "endAt": .string(ApplePersonalToolParsing.iso8601(event.endDate)),
            "calendarId": .string(event.calendar.calendarIdentifier),
            "calendarTitle": .string(event.calendar.title),
            "description": event.notes.map(AgentValue.string) ?? .null,
            "location": event.location.map(AgentValue.string) ?? .null,
            "timezone": event.timeZone.map { .string($0.identifier) } ?? .null,
            "allDay": .bool(event.isAllDay),
            "reminderMinutes": .array(alarms),
            "hasRecurrenceRules": .bool(!(event.recurrenceRules ?? []).isEmpty),
        ])
    }

    private func calendarTypeName(_ type: EKCalendarType) -> String {
        switch type {
        case .local: "local"
        case .calDAV: "caldav"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }
}
