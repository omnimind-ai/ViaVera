import Foundation
import HealthKit

@MainActor
final class AppleHealthKitService {
    private struct AuthorizationRequestOutcome {
        let statusBeforeRequest: HKAuthorizationRequestStatus
        let statusAfterRequest: HKAuthorizationRequestStatus?
        let requestedAuthorization: Bool
        let authorizationPending: Bool
    }

    private struct QueryRange {
        let startAt: Date
        let endAt: Date
    }

    private static let maximumQueryYears = 10

    private let healthStore: HKHealthStore
    private let authorizationProvider: any AppleHealthKitAuthorizing
    private let healthDataIsAvailable: @MainActor () -> Bool
    private var authorizationRequestTask: Task<Void, Never>?
    private var authorizationRequestStatusBefore: HKAuthorizationRequestStatus?
    private var authorizationRequestFailure: String?

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        authorizationProvider: (any AppleHealthKitAuthorizing)? = nil,
        healthDataIsAvailable: @escaping @MainActor () -> Bool = {
            HKHealthStore.isHealthDataAvailable()
        }
    ) {
        self.healthStore = healthStore
        self.authorizationProvider = authorizationProvider ?? healthStore
        self.healthDataIsAvailable = healthDataIsAvailable
    }

    func listDataTypes(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        _ = arguments

        let isAvailable = healthDataIsAvailable()
        return AgentToolExecutionResult(
            content: isAvailable
                ? "HealthKit is available. Listed the read-only health data types supported by the agent."
                : "HealthKit is not available on this device.",
            metadata: [
                "available": .bool(isAvailable),
                "quantityTypes": .array(AppleHealthQuantityType.allCases.map(quantityTypeValue)),
                "categoryTypes": .array(AppleHealthCategoryType.allCases.map(categoryTypeValue)),
                "workoutsSupported": .bool(true),
                "writeSupported": .bool(false),
                "backend": .string("healthkit"),
            ]
        )
    }

    func requestAccess(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let quantityNames = try stringArray(
            arguments,
            name: "quantityTypes",
            maximumCount: AppleHealthQuantityType.allCases.count
        )
        let categoryNames = try stringArray(
            arguments,
            name: "categoryTypes",
            maximumCount: AppleHealthCategoryType.allCases.count
        )
        let includeWorkouts = try arguments.bool("includeWorkouts", default: false)

        let quantityTypes = try quantityNames.map(quantityType(named:))
        let categoryTypes = try categoryNames.map(categoryType(named:))
        var readTypes = Set<HKObjectType>(quantityTypes.map(\.healthKitType))
        readTypes.formUnion(categoryTypes.map(\.healthKitType))
        if includeWorkouts {
            readTypes.insert(HKObjectType.workoutType())
        }
        guard !readTypes.isEmpty else {
            throw OmniAgentToolError(
                "Select at least one quantity type, category type, or includeWorkouts=true."
            )
        }

        let outcome = try await beginReadAccessRequest(for: readTypes)
        let content = if outcome.authorizationPending {
            if outcome.requestedAuthorization {
                "The HealthKit authorization request started. Ask the user to finish the system sheet, then stop this turn. Run the health query only after the user sends a new message confirming the sheet is complete."
            } else {
                "A HealthKit authorization request is already waiting for the user. Stop this turn and ask the user to finish the system sheet before running a health query."
            }
        } else {
            "HealthKit does not need to present another authorization sheet for these types. Apple does not reveal which read permissions the user granted; the next query must interpret an empty result accordingly."
        }
        return AgentToolExecutionResult(
            content: content,
            metadata: [
                "quantityTypes": .array(quantityTypes.map { .string($0.rawValue) }),
                "categoryTypes": .array(categoryTypes.map { .string($0.rawValue) }),
                "includeWorkouts": .bool(includeWorkouts),
                "requestStatusBefore": .string(requestStatusName(outcome.statusBeforeRequest)),
                "requestStatusAfter": .string(
                    outcome.statusAfterRequest.map(requestStatusName) ?? "pending"
                ),
                "authorizationRequested": .bool(outcome.requestedAuthorization),
                "authorizationPending": .bool(outcome.authorizationPending),
                "requiresUserInteraction": .bool(outcome.authorizationPending),
                "readAuthorizationStatus": .string("not_disclosed_by_healthkit"),
                "backend": .string("healthkit"),
            ]
        )
    }

    func quantitySamples(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let metric = try quantityType(
            named: arguments.requiredString("quantityType", maximumLength: 128)
        )
        let range = try queryRange(arguments, defaultDays: 1)
        let limit = try arguments.integer("limit", default: 100, range: 1...200) ?? 100
        let authorization = try await requireReadAccessRequestCompleted(
            for: [metric.healthKitType]
        )
        let predicate = HKQuery.predicateForSamples(
            withStart: range.startAt,
            end: range.endAt
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: metric.healthKitType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        let samples = try await descriptor.result(for: healthStore)

        var metadata = queryMetadata(
            range: range,
            authorization: authorization,
            isEmpty: samples.isEmpty
        )
        metadata.merge([
            "quantityType": .string(metric.rawValue),
            "unit": .string(metric.unitSymbol),
            "samples": .array(samples.map { quantitySampleValue($0, metric: metric) }),
            "count": .number(Double(samples.count)),
            "limit": .number(Double(limit)),
        ]) { _, new in new }

        return AgentToolExecutionResult(
            content: samples.isEmpty
                ? emptyQueryMessage(for: metric.rawValue)
                : "Found \(samples.count) HealthKit \(metric.rawValue) sample(s).",
            metadata: metadata
        )
    }

    func quantityStatistics(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let metric = try quantityType(
            named: arguments.requiredString("quantityType", maximumLength: 128)
        )
        let statisticName = try arguments.requiredString("statistic", maximumLength: 32)
        guard let statistic = AppleHealthStatistic(rawValue: statisticName) else {
            throw OmniAgentToolError(
                "Unsupported statistic '\(statisticName)'. Use one of: \(AppleHealthStatistic.allCases.map(\.rawValue).joined(separator: ", "))."
            )
        }
        try validate(statistic: statistic, for: metric)

        let range = try queryRange(arguments, defaultDays: 1)
        let authorization = try await requireReadAccessRequestCompleted(
            for: [metric.healthKitType]
        )
        let predicate = HKQuery.predicateForSamples(
            withStart: range.startAt,
            end: range.endAt
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: metric.healthKitType, predicate: predicate),
            options: statistic.healthKitOption
        )
        let statistics = try await descriptor.result(for: healthStore)
        let quantity = statistics.flatMap(statistic.quantity(from:))
        let value = quantity?.doubleValue(for: metric.unit)

        var metadata = queryMetadata(
            range: range,
            authorization: authorization,
            isEmpty: value == nil
        )
        metadata.merge([
            "quantityType": .string(metric.rawValue),
            "statistic": .string(statistic.rawValue),
            "value": value.map(AgentValue.number) ?? .null,
            "unit": .string(metric.unitSymbol),
            "hasData": .bool(value != nil),
        ]) { _, new in new }

        return AgentToolExecutionResult(
            content: value == nil
                ? emptyQueryMessage(for: metric.rawValue)
                : "Calculated HealthKit \(statistic.rawValue) for \(metric.rawValue).",
            metadata: metadata
        )
    }

    func categorySamples(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let category = try categoryType(
            named: arguments.requiredString("categoryType", maximumLength: 128)
        )
        let range = try queryRange(arguments, defaultDays: 7)
        let limit = try arguments.integer("limit", default: 100, range: 1...200) ?? 100
        let authorization = try await requireReadAccessRequestCompleted(
            for: [category.healthKitType]
        )
        let predicate = HKQuery.predicateForSamples(
            withStart: range.startAt,
            end: range.endAt
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [
                .categorySample(type: category.healthKitType, predicate: predicate),
            ],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        let samples = try await descriptor.result(for: healthStore)

        var metadata = queryMetadata(
            range: range,
            authorization: authorization,
            isEmpty: samples.isEmpty
        )
        metadata.merge([
            "categoryType": .string(category.rawValue),
            "samples": .array(samples.map { categorySampleValue($0, category: category) }),
            "count": .number(Double(samples.count)),
            "limit": .number(Double(limit)),
        ]) { _, new in new }

        return AgentToolExecutionResult(
            content: samples.isEmpty
                ? emptyQueryMessage(for: category.rawValue)
                : "Found \(samples.count) HealthKit \(category.rawValue) sample(s).",
            metadata: metadata
        )
    }

    func listWorkouts(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let range = try queryRange(arguments, defaultDays: 30)
        let limit = try arguments.integer("limit", default: 50, range: 1...100) ?? 50
        let workoutType = HKObjectType.workoutType()
        let authorization = try await requireReadAccessRequestCompleted(for: [workoutType])
        let predicate = HKQuery.predicateForSamples(
            withStart: range.startAt,
            end: range.endAt
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        let workouts = try await descriptor.result(for: healthStore)

        var metadata = queryMetadata(
            range: range,
            authorization: authorization,
            isEmpty: workouts.isEmpty
        )
        metadata.merge([
            "workouts": .array(workouts.map(workoutValue)),
            "count": .number(Double(workouts.count)),
            "limit": .number(Double(limit)),
        ]) { _, new in new }

        return AgentToolExecutionResult(
            content: workouts.isEmpty
                ? emptyQueryMessage(for: "workout")
                : "Found \(workouts.count) HealthKit workout(s).",
            metadata: metadata
        )
    }

    static func validateQueryRange(startAt: Date, endAt: Date) throws {
        guard endAt > startAt else {
            throw OmniAgentToolError("HealthKit query endAt must be later than startAt.")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let maximumEnd = calendar.date(
            byAdding: .year,
            value: maximumQueryYears,
            to: startAt
        ), endAt <= maximumEnd else {
            throw ApplePersonalToolError(
                "HealthKit queries may span at most \(maximumQueryYears) years. Split the request into smaller date ranges.",
                code: "range_too_large",
                backend: "healthkit",
                guidance: "Split the HealthKit query into ranges of no more than \(maximumQueryYears) years."
            )
        }
    }

    private func beginReadAccessRequest(
        for readTypes: Set<HKObjectType>
    ) async throws -> AuthorizationRequestOutcome {
        try ensureHealthDataIsAvailable()

        if authorizationRequestTask != nil {
            return AuthorizationRequestOutcome(
                statusBeforeRequest: authorizationRequestStatusBefore ?? .unknown,
                statusAfterRequest: nil,
                requestedAuthorization: false,
                authorizationPending: true
            )
        }

        let emptyShareTypes = Set<HKSampleType>()
        let statusBefore = try await authorizationProvider.statusForAuthorizationRequest(
            toShare: emptyShareTypes,
            read: readTypes
        )
        guard statusBefore != .unnecessary else {
            authorizationRequestFailure = nil
            authorizationRequestStatusBefore = nil
            return AuthorizationRequestOutcome(
                statusBeforeRequest: statusBefore,
                statusAfterRequest: statusBefore,
                requestedAuthorization: false,
                authorizationPending: false
            )
        }

        authorizationRequestFailure = nil
        authorizationRequestStatusBefore = statusBefore
        authorizationRequestTask = Task { @MainActor [weak self, readTypes] in
            guard let self else { return }
            defer { authorizationRequestTask = nil }

            do {
                try await authorizationProvider.requestAuthorization(
                    toShare: Set<HKSampleType>(),
                    read: readTypes
                )
            } catch is CancellationError {
                return
            } catch {
                authorizationRequestFailure = error.localizedDescription
            }
        }

        return AuthorizationRequestOutcome(
            statusBeforeRequest: statusBefore,
            statusAfterRequest: nil,
            requestedAuthorization: true,
            authorizationPending: true
        )
    }

    private func requireReadAccessRequestCompleted(
        for readTypes: Set<HKObjectType>
    ) async throws -> AuthorizationRequestOutcome {
        try ensureHealthDataIsAvailable()

        if authorizationRequestTask != nil {
            throw ApplePersonalToolError(
                "HealthKit authorization is waiting for the user to finish the system sheet.",
                code: "authorization_pending",
                permission: "healthkit",
                authorizationStatus: "pending_user_interaction",
                backend: "healthkit",
                requiresUserInteraction: true,
                guidance: "Stop this turn and ask the user to finish the HealthKit authorization sheet. Retry the query only after a new user message confirms completion."
            )
        }

        if let authorizationRequestFailure {
            throw ApplePersonalToolError(
                "The previous HealthKit authorization request failed: \(authorizationRequestFailure)",
                code: "authorization_request_failed",
                permission: "healthkit",
                authorizationStatus: "request_failed",
                backend: "healthkit",
                requiresUserInteraction: true,
                guidance: "Call healthkit_request_access again only if the user still wants to grant access."
            )
        }

        let emptyShareTypes = Set<HKSampleType>()
        let status = try await authorizationProvider.statusForAuthorizationRequest(
            toShare: emptyShareTypes,
            read: readTypes
        )
        guard status == .unnecessary else {
            throw ApplePersonalToolError(
                "HealthKit access has not been requested for these data types.",
                code: "authorization_required",
                permission: "healthkit",
                authorizationStatus: requestStatusName(status),
                backend: "healthkit",
                requiresUserInteraction: true,
                guidance: "Call healthkit_request_access for the requested types. When it reports authorizationPending=true, stop and ask the user to finish the system sheet before retrying the query."
            )
        }

        authorizationRequestFailure = nil
        return AuthorizationRequestOutcome(
            statusBeforeRequest: status,
            statusAfterRequest: status,
            requestedAuthorization: false,
            authorizationPending: false
        )
    }

    private func ensureHealthDataIsAvailable() throws {
        guard healthDataIsAvailable() else {
            throw ApplePersonalToolError(
                "HealthKit data is not available on this device.",
                code: "health_data_unavailable",
                permission: "healthkit",
                backend: "healthkit"
            )
        }
    }

#if DEBUG
    func cancelPendingAuthorizationRequestForTesting() {
        authorizationRequestTask?.cancel()
        authorizationRequestTask = nil
    }
#endif

    private func queryRange(
        _ arguments: OmniToolArguments,
        defaultDays: Int
    ) throws -> QueryRange {
        let endAt = if let rawEnd = try arguments.optionalString(
            "endAt",
            maximumLength: 128
        ) {
            try ApplePersonalToolParsing.date(rawEnd, parameterName: "endAt")
        } else {
            Date.now
        }
        let startAt = if let rawStart = try arguments.optionalString(
            "startAt",
            maximumLength: 128
        ) {
            try ApplePersonalToolParsing.date(rawStart, parameterName: "startAt")
        } else {
            Calendar(identifier: .gregorian).date(
                byAdding: .day,
                value: -defaultDays,
                to: endAt
            ) ?? endAt.addingTimeInterval(-Double(defaultDays) * 86_400)
        }

        try Self.validateQueryRange(startAt: startAt, endAt: endAt)
        return QueryRange(startAt: startAt, endAt: endAt)
    }

    private func quantityType(named name: String) throws -> AppleHealthQuantityType {
        guard let type = AppleHealthQuantityType(rawValue: name) else {
            throw OmniAgentToolError(
                "Unsupported HealthKit quantity type '\(name)'. Use healthkit_data_types to list supported types."
            )
        }
        return type
    }

    private func categoryType(named name: String) throws -> AppleHealthCategoryType {
        guard let type = AppleHealthCategoryType(rawValue: name) else {
            throw OmniAgentToolError(
                "Unsupported HealthKit category type '\(name)'. Use healthkit_data_types to list supported types."
            )
        }
        return type
    }

    private func stringArray(
        _ arguments: OmniToolArguments,
        name: String,
        maximumCount: Int
    ) throws -> [String] {
        guard let value = arguments.values[name], value != .null else { return [] }
        guard case let .array(values) = value, values.count <= maximumCount else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected at most \(maximumCount) strings."
            )
        }
        let strings = try values.map { value in
            guard case let .string(string) = value, string.count <= 128 else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': every item must be a string of at most 128 characters."
                )
            }
            return string
        }
        return Array(Set(strings)).sorted()
    }

    private func validate(
        statistic: AppleHealthStatistic,
        for metric: AppleHealthQuantityType
    ) throws {
        let isValid = switch metric.aggregation {
        case .cumulative: statistic == .sum
        case .discrete: statistic != .sum
        }
        guard isValid else {
            let allowed = metric.aggregation == .cumulative
                ? "sum"
                : "average, minimum, maximum"
            throw OmniAgentToolError(
                "Statistic '\(statistic.rawValue)' is incompatible with \(metric.rawValue). Allowed statistics: \(allowed)."
            )
        }
    }

    private func queryMetadata(
        range: QueryRange,
        authorization: AuthorizationRequestOutcome,
        isEmpty: Bool
    ) -> [String: AgentValue] {
        [
            "startAt": .string(ApplePersonalToolParsing.iso8601(range.startAt)),
            "endAt": .string(ApplePersonalToolParsing.iso8601(range.endAt)),
            "requestStatusBefore": .string(requestStatusName(authorization.statusBeforeRequest)),
            "requestStatusAfter": .string(
                authorization.statusAfterRequest.map(requestStatusName) ?? "pending"
            ),
            "authorizationRequested": .bool(authorization.requestedAuthorization),
            "authorizationPending": .bool(authorization.authorizationPending),
            "readAuthorizationStatus": .string("not_disclosed_by_healthkit"),
            "emptyResultMayMeanNoReadPermission": .bool(isEmpty),
            "backend": .string("healthkit"),
            "readOnly": .bool(true),
        ]
    }

    private func quantityTypeValue(_ type: AppleHealthQuantityType) -> AgentValue {
        .object([
            "name": .string(type.rawValue),
            "unit": .string(type.unitSymbol),
            "aggregation": .string(type.aggregation.rawValue),
            "statistics": .array(
                (type.aggregation == .cumulative
                    ? [AppleHealthStatistic.sum]
                    : [.average, .minimum, .maximum])
                    .map { .string($0.rawValue) }
            ),
        ])
    }

    private func categoryTypeValue(_ type: AppleHealthCategoryType) -> AgentValue {
        .object([
            "name": .string(type.rawValue),
        ])
    }

    private func quantitySampleValue(
        _ sample: HKQuantitySample,
        metric: AppleHealthQuantityType
    ) -> AgentValue {
        .object([
            "sampleId": .string(sample.uuid.uuidString),
            "value": .number(sample.quantity.doubleValue(for: metric.unit)),
            "unit": .string(metric.unitSymbol),
            "startAt": .string(ApplePersonalToolParsing.iso8601(sample.startDate)),
            "endAt": .string(ApplePersonalToolParsing.iso8601(sample.endDate)),
            "durationSeconds": .number(sample.endDate.timeIntervalSince(sample.startDate)),
            "source": sourceValue(sample.sourceRevision),
        ])
    }

    private func categorySampleValue(
        _ sample: HKCategorySample,
        category: AppleHealthCategoryType
    ) -> AgentValue {
        .object([
            "sampleId": .string(sample.uuid.uuidString),
            "value": .number(Double(sample.value)),
            "valueName": .string(category.valueName(sample.value)),
            "startAt": .string(ApplePersonalToolParsing.iso8601(sample.startDate)),
            "endAt": .string(ApplePersonalToolParsing.iso8601(sample.endDate)),
            "durationSeconds": .number(sample.endDate.timeIntervalSince(sample.startDate)),
            "source": sourceValue(sample.sourceRevision),
        ])
    }

    private func workoutValue(_ workout: HKWorkout) -> AgentValue {
        let energyType = AppleHealthQuantityType.activeEnergyBurned
        let distanceTypes: [AppleHealthQuantityType] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]
        var distances: [String: AgentValue] = [:]
        for metric in distanceTypes {
            if let quantity = workout.statistics(for: metric.healthKitType)?.sumQuantity() {
                distances[metric.rawValue] = .number(quantity.doubleValue(for: metric.unit))
            }
        }
        let energy = workout.statistics(for: energyType.healthKitType)?
            .sumQuantity()?
            .doubleValue(for: energyType.unit)

        return .object([
            "workoutId": .string(workout.uuid.uuidString),
            "activityType": .string(workoutActivityName(workout.workoutActivityType)),
            "activityTypeCode": .number(Double(workout.workoutActivityType.rawValue)),
            "startAt": .string(ApplePersonalToolParsing.iso8601(workout.startDate)),
            "endAt": .string(ApplePersonalToolParsing.iso8601(workout.endDate)),
            "durationSeconds": .number(workout.duration),
            "activeEnergyBurned": energy.map(AgentValue.number) ?? .null,
            "activeEnergyUnit": .string(energyType.unitSymbol),
            "distancesMeters": .object(distances),
            "source": sourceValue(workout.sourceRevision),
        ])
    }

    private func sourceValue(_ revision: HKSourceRevision) -> AgentValue {
        .object([
            "name": .string(revision.source.name),
            "bundleIdentifier": .string(revision.source.bundleIdentifier),
        ])
    }

    private func workoutActivityName(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .running: "running"
        case .walking: "walking"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .hiking: "hiking"
        case .functionalStrengthTraining: "functional_strength_training"
        case .traditionalStrengthTraining: "traditional_strength_training"
        case .highIntensityIntervalTraining: "high_intensity_interval_training"
        case .yoga: "yoga"
        case .mindAndBody: "mind_and_body"
        case .pilates: "pilates"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        case .stairClimbing: "stair_climbing"
        case .coreTraining: "core_training"
        case .other: "other"
        default: "activity_\(activity.rawValue)"
        }
    }

    private func requestStatusName(_ status: HKAuthorizationRequestStatus) -> String {
        switch status {
        case .unknown: "unknown"
        case .shouldRequest: "should_request"
        case .unnecessary: "unnecessary"
        @unknown default: "unknown"
        }
    }

    private func emptyQueryMessage(for type: String) -> String {
        "No accessible HealthKit \(type) data was found in the requested range. HealthKit intentionally does not disclose whether an empty result means no data or denied read permission."
    }
}
