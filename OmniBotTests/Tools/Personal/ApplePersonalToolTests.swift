import Foundation
import Testing
#if os(macOS)
import UserNotifications
#endif
@testable import Via_Vera

@Suite("Apple personal tools")
struct ApplePersonalToolTests {
    @Test("Calendar event queries reject ranges longer than ten years before EventKit expansion")
    @MainActor
    func calendarEventQueryRangeIsBounded() throws {
        let start = try Date("2020-02-29T12:00:00Z", strategy: .iso8601)
        let maximumEnd = try Date("2030-02-28T12:00:00Z", strategy: .iso8601)

        try AppleCalendarService.validateEventQueryRange(
            startAt: start,
            endAt: maximumEnd
        )

        do {
            try AppleCalendarService.validateEventQueryRange(
                startAt: start,
                endAt: maximumEnd.addingTimeInterval(1)
            )
            Issue.record("Expected a range_too_large error")
        } catch let error as ApplePersonalToolError {
            #expect(error.code == "range_too_large")
            #expect(error.backend == "eventkit")
            #expect(error.guidance?.contains("10 years") == true)
            #expect(!error.requiresSystemSettings)
        }
    }

    #if os(macOS)
    @Test("macOS alarm service retains a foreground notification presenter")
    @MainActor
    func macOSAlarmForegroundPresenterIsInstalled() {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        defer { center.delegate = previousDelegate }

        let service = AppleAlarmService(
            recordFileURL: FileManager.default.temporaryDirectory.appending(
                path: "\(UUID().uuidString)-alarms.json"
            ),
            notificationCenter: center
        )

        #expect(service.isForegroundNotificationPresentationInstalled)
        #expect(
            AppleUserNotificationCenterDelegate.foregroundPresentationOptions
                == [.banner, .list, .sound]
        )
        withExtendedLifetime(service) {}
    }
    #endif

    @Test("Alarm records stay bounded and reconcile against active platform alarms")
    func alarmRecordReconciliation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppleAlarmRecordStore(
            fileURL: directory.appending(path: "alarms.json")
        )
        let createdAt = try Date("2026-07-13T09:00:00Z", strategy: .iso8601)
        let first = OmniBotAlarmRecord(
            alarmID: "first",
            backend: "alarmkit",
            title: "Wake up",
            message: "Morning",
            triggerAt: createdAt.addingTimeInterval(3_600),
            timeZoneIdentifier: "Asia/Shanghai",
            exact: true,
            createdAt: createdAt
        )
        let second = OmniBotAlarmRecord(
            alarmID: "second",
            backend: "user_notifications",
            title: "Meeting",
            message: nil,
            triggerAt: createdAt.addingTimeInterval(7_200),
            timeZoneIdentifier: "UTC",
            exact: false,
            createdAt: createdAt
        )

        try await store.upsert(first)
        try await store.upsert(second)
        #expect(try await store.all().count == 2)

        let active = try await store.reconcile(activeAlarmIDs: ["second"])
        #expect(active == [second])
        #expect(try await store.all() == [second])

        #expect(try await store.remove(alarmID: "second"))
        #expect(try await store.all().isEmpty)
    }

    @Test("Contact schemas require labeled phone and email objects and expose no note")
    func contactSchemasUseLabeledValues() throws {
        let definitions = Dictionary(
            uniqueKeysWithValues: OmniAgentToolDefinitions.all.map { ($0.name, $0) }
        )
        for name in ["contacts_create", "contacts_update"] {
            let definition = try #require(definitions[name])
            let properties = try #require(
                definition.parameters.objectValue?["properties"]?.objectValue
            )
            #expect(properties["note"] == nil)
            for field in ["phones", "emails"] {
                let schema = try #require(properties[field]?.objectValue)
                let items = try #require(schema["items"]?.objectValue)
                #expect(items["type"] == .string("object"))
                let itemProperties = try #require(items["properties"]?.objectValue)
                #expect(itemProperties["label"] != nil)
                #expect(itemProperties["value"] != nil)
            }
        }
    }

    @Test("Limited Contacts scope directs the user to system Settings")
    func limitedContactsErrorIsActionable() {
        let error = ApplePersonalToolError(
            "Selection required.",
            code: "limited_scope",
            permission: "contacts",
            authorizationStatus: "limited",
            backend: "contacts",
            requiresSystemSettings: true,
            guidance: "Expand Contacts access in Settings."
        )

        #expect(error.metadata["requiresUserInteraction"] == .bool(false))
        #expect(error.metadata["requiresSystemSettings"] == .bool(true))
        #expect(error.metadata["authorizationStatus"] == .string("limited"))
        #expect(error.actions.map(\.type) == ["open_system_settings"])
    }
}
