import HealthKit

@MainActor
protocol AppleHealthKitAuthorizing: AnyObject {
    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws
}

extension HKHealthStore: AppleHealthKitAuthorizing {}
