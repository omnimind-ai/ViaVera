import Foundation
import Testing
@testable import Via_Vera

@Suite("iOS permission settings")
@MainActor
struct IOSPermissionSettingsModelTests {
    @Test("Refresh loads persisted Agent access switches in catalog order")
    func refreshesStatusesAndSwitches() async throws {
        let storage = try makePermissionStorage()
        defer { storage.defaults.removePersistentDomain(forName: storage.suiteName) }
        await storage.store.setEnabled(true, for: .healthKit)
        await storage.store.setEnabled(true, for: .contacts)
        let statuses: [IOSPermissionKind: IOSPermissionAuthorization] = [
            .healthKit: .requested,
            .calendars: .authorized,
            .contacts: .limited,
            .alarms: .authorized,
        ]
        let client = TestIOSPermissionAuthorizationClient(statuses: statuses)
        let model = IOSPermissionSettingsModel(
            authorizationClient: client,
            permissionStore: storage.store
        )

        await model.refresh()

        #expect(model.permissions.map(\.kind) == IOSPermissionKind.availableOnCurrentPlatform)
        #expect(model.permissions.map(\.authorization) == IOSPermissionKind
            .availableOnCurrentPlatform
            .map { statuses[$0] ?? .unknown })
        #expect(model.permissions.map(\.isEnabled) == IOSPermissionKind
            .availableOnCurrentPlatform
            .map { $0 == .healthKit || $0 == .contacts })
    }

    @Test("First switch-on requests system authorization and enables Agent access")
    func firstEnableRequestsAuthorization() async throws {
        let storage = try makePermissionStorage()
        defer { storage.defaults.removePersistentDomain(forName: storage.suiteName) }
        let client = TestIOSPermissionAuthorizationClient(statuses: [
            .healthKit: .notDetermined,
        ])
        client.statusAfterRequest = .requested
        let model = IOSPermissionSettingsModel(
            authorizationClient: client,
            permissionStore: storage.store
        )
        await model.refresh()
        let health = try #require(
            model.permissions.first(where: { $0.kind == .healthKit })
        )

        await model.setEnabled(true, for: health)

        #expect(client.requestedPermissions == [.healthKit])
        #expect(health.authorization == .requested)
        #expect(health.isEnabled)
        #expect(model.requestingPermission == nil)
        #expect(model.alert == nil)
        let storedValue = await storage.store.isEnabled(.healthKit)
        #expect(storedValue)
    }

    @Test("Switch-off persists immediately without another system request")
    func disablePersistsWithoutRequest() async throws {
        let storage = try makePermissionStorage()
        defer { storage.defaults.removePersistentDomain(forName: storage.suiteName) }
        await storage.store.setEnabled(true, for: .calendars)
        let client = TestIOSPermissionAuthorizationClient(statuses: [
            .calendars: .authorized,
        ])
        let model = IOSPermissionSettingsModel(
            authorizationClient: client,
            permissionStore: storage.store
        )
        await model.refresh()
        let calendars = try #require(
            model.permissions.first(where: { $0.kind == .calendars })
        )

        await model.setEnabled(false, for: calendars)

        #expect(!calendars.isEnabled)
        #expect(client.requestedPermissions.isEmpty)
        let storedValue = await storage.store.isEnabled(.calendars)
        #expect(!storedValue)
    }

    @Test("A write-only calendar grant requests an upgrade to full access")
    func writeOnlyCalendarRequestsUpgrade() async throws {
        let storage = try makePermissionStorage()
        defer { storage.defaults.removePersistentDomain(forName: storage.suiteName) }
        let client = TestIOSPermissionAuthorizationClient(statuses: [
            .calendars: .writeOnly,
        ])
        client.statusAfterRequest = .authorized
        let model = IOSPermissionSettingsModel(
            authorizationClient: client,
            permissionStore: storage.store
        )
        await model.refresh()
        let calendars = try #require(
            model.permissions.first(where: { $0.kind == .calendars })
        )

        await model.setEnabled(true, for: calendars)

        #expect(client.requestedPermissions == [.calendars])
        #expect(calendars.authorization == .authorized)
        #expect(calendars.isEnabled)
    }

    @Test("A denied system authorization turns the switch back off")
    func denialRevertsSwitch() async throws {
        let storage = try makePermissionStorage()
        defer { storage.defaults.removePersistentDomain(forName: storage.suiteName) }
        let client = TestIOSPermissionAuthorizationClient(statuses: [
            .contacts: .notDetermined,
        ])
        client.statusAfterRequest = .denied
        let model = IOSPermissionSettingsModel(
            authorizationClient: client,
            permissionStore: storage.store
        )
        await model.refresh()
        let contacts = try #require(
            model.permissions.first(where: { $0.kind == .contacts })
        )

        await model.setEnabled(true, for: contacts)

        #expect(!contacts.isEnabled)
        #expect(model.alert?.title == "无法启用通讯录权限")
        #expect(model.alert?.offersSystemSettings == true)
        let storedValue = await storage.store.isEnabled(.contacts)
        #expect(!storedValue)
    }

    @Test("Authorization request failures remain visible and leave access off")
    func requestFailurePresentsAlert() async throws {
        let storage = try makePermissionStorage()
        defer { storage.defaults.removePersistentDomain(forName: storage.suiteName) }
        let client = TestIOSPermissionAuthorizationClient(statuses: [
            .calendars: .notDetermined,
        ])
        client.requestError = IOSPermissionRequestError.healthDataUnavailable
        let model = IOSPermissionSettingsModel(
            authorizationClient: client,
            permissionStore: storage.store
        )
        await model.refresh()
        let calendars = try #require(
            model.permissions.first(where: { $0.kind == .calendars })
        )

        await model.setEnabled(true, for: calendars)

        #expect(model.alert?.title == "无法启用日历权限")
        #expect(model.alert?.message == "此设备无法使用 HealthKit。")
        #expect(!calendars.isEnabled)
    }

    @Test("Authorization states expose only effective Agent access")
    func authorizationAccessMapping() {
        #expect(IOSPermissionAuthorization.authorized.allowsAgentAccess)
        #expect(IOSPermissionAuthorization.limited.allowsAgentAccess)
        #expect(IOSPermissionAuthorization.requested.allowsAgentAccess)
        #expect(!IOSPermissionAuthorization.notDetermined.allowsAgentAccess)
        #expect(!IOSPermissionAuthorization.writeOnly.allowsAgentAccess)
        #expect(!IOSPermissionAuthorization.denied.allowsAgentAccess)
        #expect(!IOSPermissionAuthorization.restricted.allowsAgentAccess)
        #expect(!IOSPermissionAuthorization.unavailable.allowsAgentAccess)
        #expect(!IOSPermissionAuthorization.unknown.allowsAgentAccess)
    }

    @Test("Current platform exposes only permissions backed by native APIs")
    func currentPlatformPermissionCatalog() {
#if os(macOS)
        #expect(IOSPermissionKind.availableOnCurrentPlatform == [
            .healthKit,
            .calendars,
            .contacts,
        ])
#else
        #expect(IOSPermissionKind.availableOnCurrentPlatform == IOSPermissionKind.allCases)
#endif
    }

    @Test("Agent permission store persists values across instances")
    func storePersistsAcrossInstances() async throws {
        let storage = try makePermissionStorage()
        defer { storage.defaults.removePersistentDomain(forName: storage.suiteName) }
        await storage.store.setEnabled(true, for: .healthKit)
        let secondStore = AgentPermissionStore(defaults: storage.defaults)

        let storedValue = await secondStore.isEnabled(.healthKit)

        #expect(storedValue)
    }

    private func makePermissionStorage() throws -> (
        store: AgentPermissionStore,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "IOSPermissionSettingsModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (AgentPermissionStore(defaults: defaults), defaults, suiteName)
    }
}
