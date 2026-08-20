import Foundation

extension OmniAgentToolExecutor {
    func currentTime(
        _ arguments: OmniToolArguments,
        now: Date = Date()
    ) -> AgentToolExecutionResult {
        _ = arguments
        let localTimeZone = TimeZone.current
        let localFormatter = ISO8601DateFormatter()
        localFormatter.timeZone = localTimeZone
        localFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let utcFormatter = ISO8601DateFormatter()
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let local = localFormatter.string(from: now)
        let utc = utcFormatter.string(from: now)
        return AgentToolExecutionResult(
            content: "Local: \(local)\nUTC: \(utc)\nTime zone: \(localTimeZone.identifier)",
            metadata: [
                "local": .string(local),
                "utc": .string(utc),
                "timeZone": .string(localTimeZone.identifier),
                "secondsFromGMT": .number(Double(localTimeZone.secondsFromGMT(for: now))),
            ]
        )
    }
}
