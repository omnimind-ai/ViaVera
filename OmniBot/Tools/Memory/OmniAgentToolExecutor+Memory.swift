import Foundation

extension OmniAgentToolExecutor {
    func searchMemory(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let query = try arguments.requiredString("query", maximumLength: 8_192)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OmniAgentToolError("Parameter 'query' must not be empty.")
        }
        let limit = try arguments.integer("limit", default: 8, range: 1...50) ?? 8
        let hits = try await memoryStore.search(query, limit: limit)
        let lines = hits.map { hit in
            "[\(memorySourceName(hit.source)) score=\(formattedScore(hit.score)) id=\(hit.id)] \(hit.text)"
        }
        let content = lines.isEmpty ? "No memory matches found." : lines.joined(separator: "\n")
        let bounded = boundedText(content, maximumCharacters: limits.maximumTerminalOutputCharacters)
        return AgentToolExecutionResult(
            content: bounded.text,
            metadata: [
                "query": .string(query),
                "hitCount": .number(Double(hits.count)),
                "truncated": .bool(bounded.truncated),
            ]
        )
    }

    func loadMemory(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let scope = try arguments.optionalString("scope", default: "all") ?? "all"
        guard ["all", "longterm", "daily", "failures"].contains(scope) else {
            throw OmniAgentToolError(
                "Invalid parameter 'scope': expected 'all', 'longterm', 'daily', or 'failures'."
            )
        }
        let date = try memoryDate(arguments)
        var sections: [String] = []
        if scope == "all" || scope == "longterm" {
            let longTerm = try await memoryStore.loadLongTermMemory()
            sections.append("# Long-term memory\n\n\(longTerm)")
        }
        if scope == "all" || scope == "daily" {
            let daily = try await memoryStore.loadDailyMemory(at: date)
            sections.append("# Daily memory\n\n\(daily)")
        }
        if scope == "all" || scope == "failures" {
            let failures = try await memoryStore.loadHarnessFailures()
            sections.append("# Harness failures\n\n\(failures)")
        }
        let content = sections.joined(separator: "\n\n")
        let bounded = boundedText(
            content.isEmpty ? "(memory is empty)" : content,
            maximumCharacters: limits.maximumTerminalOutputCharacters
        )
        return AgentToolExecutionResult(
            content: bounded.text,
            metadata: [
                "scope": .string(scope),
                "date": .string(ISO8601DateFormatter().string(from: date)),
                "truncated": .bool(bounded.truncated),
            ]
        )
    }

    func writeDailyMemory(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let text = try arguments.requiredString("text", maximumLength: 32_768)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OmniAgentToolError("Parameter 'text' must not be empty.")
        }
        let date = try memoryDate(arguments)
        let inserted = try await memoryStore.appendDailyMemory(text, at: date)
        return AgentToolExecutionResult(
            content: inserted
                ? "Daily memory entry saved."
                : "Daily memory already contained this entry; no duplicate was written.",
            metadata: [
                "inserted": .bool(inserted),
                "date": .string(ISO8601DateFormatter().string(from: date)),
            ]
        )
    }

    func upsertLongTermMemory(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let text = try arguments.requiredString("text", maximumLength: 32_768)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OmniAgentToolError("Parameter 'text' must not be empty.")
        }
        let inserted = try await memoryStore.upsertLongTermMemory(text)
        return AgentToolExecutionResult(
            content: inserted
                ? "Long-term memory entry saved."
                : "Long-term memory already contained this entry; no duplicate was written.",
            metadata: ["inserted": .bool(inserted)]
        )
    }

    private func memoryDate(_ arguments: OmniToolArguments) throws -> Date {
        guard let raw = try arguments.optionalString(
            "date",
            default: nil,
            maximumLength: 64
        ) else {
            return Date()
        }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: raw) {
            return date
        }
        throw OmniAgentToolError(
            "Invalid parameter 'date': expected an ISO-8601 timestamp or yyyy-MM-dd."
        )
    }

    private func memorySourceName(_ source: MemorySource) -> String {
        switch source {
        case .longTerm:
            return "longterm"
        case let .daily(date):
            return "daily:\(date)"
        case .harnessFailure:
            return "harness-failure"
        }
    }

    private func formattedScore(_ score: Double) -> String {
        String(format: "%.3f", score)
    }
}
