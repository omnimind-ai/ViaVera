import Foundation
import HealthKit
import Testing
@testable import Via_Vera

@Suite("HealthKit agent tools")
struct AppleHealthKitToolTests {
    @Test("HealthKit schemas expose the complete supported type registry")
    func schemaTypesMatchRegistry() throws {
        let definitions = Dictionary(
            uniqueKeysWithValues: OmniAgentToolDefinitions.all.map { ($0.name, $0) }
        )
        let samples = try #require(definitions["healthkit_quantity_samples"])
        let sampleProperties = try #require(
            samples.parameters.objectValue?["properties"]?.objectValue
        )
        let quantitySchema = try #require(sampleProperties["quantityType"]?.objectValue)
        let quantityNames = try #require(quantitySchema["enum"]?.arrayValue).compactMap(\.stringValue)

        #expect(Set(quantityNames) == Set(AppleHealthQuantityType.allCases.map(\.rawValue)))

        let categories = try #require(definitions["healthkit_category_samples"])
        let categoryProperties = try #require(
            categories.parameters.objectValue?["properties"]?.objectValue
        )
        let categorySchema = try #require(categoryProperties["categoryType"]?.objectValue)
        let categoryNames = try #require(categorySchema["enum"]?.arrayValue).compactMap(\.stringValue)

        #expect(Set(categoryNames) == Set(AppleHealthCategoryType.allCases.map(\.rawValue)))
    }

    @Test("HealthKit agent surface is read only")
    func toolsAreReadOnly() {
        let healthTools = OmniAgentToolDefinitions.all
            .map(\.name)
            .filter { $0.hasPrefix("healthkit_") }

        #expect(Set(healthTools) == [
            "healthkit_data_types",
            "healthkit_request_access",
            "healthkit_quantity_samples",
            "healthkit_quantity_statistics",
            "healthkit_category_samples",
            "healthkit_workout_list",
        ])
        #expect(!healthTools.contains(where: {
            $0.contains("write") || $0.contains("save") || $0.contains("delete")
        }))
    }

    @Test("HealthKit query ranges are bounded to ten years")
    @MainActor
    func queryRangesAreBounded() throws {
        let startAt = try Date("2026-07-14T00:00:00Z", strategy: .iso8601)
        let maximumEnd = try Date("2036-07-14T00:00:00Z", strategy: .iso8601)

        try AppleHealthKitService.validateQueryRange(
            startAt: startAt,
            endAt: maximumEnd
        )

        do {
            try AppleHealthKitService.validateQueryRange(
                startAt: startAt,
                endAt: maximumEnd.addingTimeInterval(1)
            )
            Issue.record("Expected a range_too_large error")
        } catch let error as ApplePersonalToolError {
            #expect(error.code == "range_too_large")
            #expect(error.backend == "healthkit")
        }
    }

    @Test("Sleep and stand category values use stable agent names")
    func categoryValueNames() {
        #expect(AppleHealthCategoryType.sleepAnalysis.valueName(0) == "in_bed")
        #expect(AppleHealthCategoryType.sleepAnalysis.valueName(3) == "asleep_core")
        #expect(AppleHealthCategoryType.sleepAnalysis.valueName(5) == "asleep_rem")
        #expect(AppleHealthCategoryType.appleStandHour.valueName(0) == "stood")
        #expect(AppleHealthCategoryType.appleStandHour.valueName(1) == "idle")
        #expect(AppleHealthCategoryType.mindfulSession.valueName(0) == "present")
    }

    @Test("Authorization tool returns while the system sheet is pending")
    @MainActor
    func authorizationToolDoesNotBlockTheAgentTurn() async throws {
        let authorization = SlowHealthKitAuthorizationProvider()
        let service = AppleHealthKitService(
            authorizationProvider: authorization,
            healthDataIsAvailable: { true }
        )
        let arguments = try healthKitArguments([
            "quantityTypes": .array([.string("step_count")]),
        ])

        let result = try await service.requestAccess(arguments)

        #expect(result.metadata["authorizationRequested"] == .bool(true))
        #expect(result.metadata["authorizationPending"] == .bool(true))
        #expect(result.metadata["requiresUserInteraction"] == .bool(true))
        #expect(result.metadata["requestStatusAfter"] == .string("pending"))
        #expect(result.content.contains("stop this turn"))

        await Task.yield()
        #expect(authorization.requestCount == 1)
        service.cancelPendingAuthorizationRequestForTesting()
    }

    @Test("HealthKit query schemas require a separate authorization step")
    func querySchemasDescribeNonBlockingAuthorizationFlow() throws {
        let definitions = Dictionary(
            uniqueKeysWithValues: OmniAgentToolDefinitions.all.map { ($0.name, $0) }
        )
        let samples = try #require(definitions["healthkit_quantity_samples"])
        let access = try #require(definitions["healthkit_request_access"])

        #expect(samples.description.contains("never presents authorization UI"))
        #expect(samples.description.contains("wait for a later user message"))
        #expect(access.description.contains("authorizationPending=true"))
        #expect(access.description.contains("stop the tool loop"))
    }

    private func healthKitArguments(
        _ values: [String: AgentValue]
    ) throws -> OmniToolArguments {
        var arguments = values
        arguments["tool_title"] = .string("HealthKit authorization test")
        let data = try JSONEncoder().encode(AgentValue.object(arguments))
        return try OmniToolArguments(call: AgentToolCall(
            id: UUID().uuidString,
            name: "healthkit_request_access",
            arguments: String(decoding: data, as: UTF8.self)
        ))
    }
}

@MainActor
private final class SlowHealthKitAuthorizationProvider: AppleHealthKitAuthorizing {
    private(set) var requestCount = 0

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        _ = typesToShare
        _ = typesToRead
        return .shouldRequest
    }

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws {
        _ = typesToShare
        _ = typesToRead
        requestCount += 1
        try await Task.sleep(for: .seconds(30))
    }
}
