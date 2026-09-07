import Foundation
import SwiftData

@ModelActor
actor ModelUsageReader {
    @concurrent
    nonisolated static func read(
        container: ModelContainer, range: ModelUsageRange, now: Date, calendar: Calendar
    ) async throws -> ModelUsageSummary {
        // Initialize the model actor off the main actor so fetching and aggregation
        // do not compete with scrolling or an ongoing conversation.
        let reader = ModelUsageReader(modelContainer: container)
        return try await reader.summary(range: range, now: now, calendar: calendar)
    }

    func summary(range: ModelUsageRange, now: Date, calendar: Calendar) throws -> ModelUsageSummary {
        let start = range.startDate(now: now, calendar: calendar)
        var descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.createdAt >= start && $0.createdAt <= now },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)]
        )
        descriptor.propertiesToFetch = [
            \.createdAt, \.roleRawValue, \.statusRawValue, \.modelID,
            \.promptTokens, \.completionTokens, \.cachedTokens, \.cacheCreationTokens,
        ]
        descriptor.fetchLimit = 500
        var entries: [ModelUsageEntry] = []
        while true {
            try Task.checkCancellation()
            let records = try modelContext.fetch(descriptor)
            entries.append(contentsOf: records.map {
                ModelUsageEntry(
                    date: $0.createdAt, role: $0.roleRawValue, status: $0.statusRawValue,
                    modelID: $0.modelID, inputTokens: $0.promptTokens,
                    outputTokens: $0.completionTokens, cachedTokens: $0.cachedTokens,
                    cacheCreationTokens: $0.cacheCreationTokens
                )
            })
            guard records.count == 500 else { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + records.count
        }
        try Task.checkCancellation()
        return ModelUsageSummary(entries: entries, range: range, now: now, calendar: calendar)
    }
}
