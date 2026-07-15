#if os(iOS)
import AlarmKit
import Contacts
import EventKit
import HealthKit

@MainActor
final class AppleIOSPermissionAuthorizationClient: IOSPermissionAuthorizationClient {
    private let contactStore: CNContactStore
    private let eventStore: EKEventStore
    private let healthStore: HKHealthStore

    init(
        contactStore: CNContactStore = CNContactStore(),
        eventStore: EKEventStore = EKEventStore(),
        healthStore: HKHealthStore = HKHealthStore()
    ) {
        self.contactStore = contactStore
        self.eventStore = eventStore
        self.healthStore = healthStore
    }

    func authorizationStatuses() async -> [IOSPermissionKind: IOSPermissionAuthorization] {
        var statuses: [IOSPermissionKind: IOSPermissionAuthorization] = [
            .calendars: calendarAuthorization,
            .contacts: contactsAuthorization,
            .alarms: alarmAuthorization,
        ]
        statuses[.healthKit] = await healthKitAuthorization()
        return statuses
    }

    func requestAuthorization(for permission: IOSPermissionKind) async throws {
        switch permission {
        case .healthKit:
            guard HKHealthStore.isHealthDataAvailable() else {
                throw IOSPermissionRequestError.healthDataUnavailable
            }
            try await healthStore.requestAuthorization(
                toShare: Set<HKSampleType>(),
                read: Self.healthKitReadTypes
            )
        case .calendars:
            _ = try await eventStore.requestFullAccessToEvents()
        case .contacts:
            _ = try await contactStore.requestAccess(for: .contacts)
        case .alarms:
            _ = try await AlarmManager.shared.requestAuthorization()
        }
    }

    private var calendarAuthorization: IOSPermissionAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .fullAccess:
            .authorized
        case .writeOnly:
            .writeOnly
        @unknown default:
            .unknown
        }
    }

    private var contactsAuthorization: IOSPermissionAuthorization {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .limited:
            .limited
        @unknown default:
            .unknown
        }
    }

    private var alarmAuthorization: IOSPermissionAuthorization {
        switch AlarmManager.shared.authorizationState {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        @unknown default:
            .unknown
        }
    }

    private func healthKitAuthorization() async -> IOSPermissionAuthorization {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do {
            let status = try await healthStore.statusForAuthorizationRequest(
                toShare: Set<HKSampleType>(),
                read: Self.healthKitReadTypes
            )
            switch status {
            case .shouldRequest:
                return .notDetermined
            case .unnecessary:
                return .requested
            case .unknown:
                return .unknown
            @unknown default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }

    private static var healthKitReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(
            AppleHealthQuantityType.allCases.map(\.healthKitType)
        )
        types.formUnion(AppleHealthCategoryType.allCases.map(\.healthKitType))
        types.insert(HKObjectType.workoutType())
        return types
    }
}
#endif
