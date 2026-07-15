import Foundation

nonisolated enum ApplePersonalToolParsing {
    static func date(_ rawValue: String, parameterName: String) throws -> Date {
        do {
            return try Date(rawValue, strategy: .iso8601)
        } catch {
            throw OmniAgentToolError(
                "Invalid parameter '\(parameterName)': expected an ISO-8601 timestamp, preferably including a UTC offset."
            )
        }
    }

    static func optionalTimeZone(
        _ rawValue: String?,
        parameterName: String = "timezone"
    ) throws -> TimeZone? {
        guard let rawValue else { return nil }
        guard let timeZone = TimeZone(identifier: rawValue) else {
            throw OmniAgentToolError(
                "Invalid parameter '\(parameterName)': '\(rawValue)' is not an IANA time-zone identifier."
            )
        }
        return timeZone
    }

    static func integerArray(
        _ arguments: OmniToolArguments,
        name: String,
        range: ClosedRange<Int>,
        maximumCount: Int
    ) throws -> [Int]? {
        guard let value = arguments.values[name], value != .null else { return nil }
        guard case let .array(values) = value, values.count <= maximumCount else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected an array with at most \(maximumCount) integers."
            )
        }

        return try values.map { value in
            guard case let .number(number) = value,
                  number.isFinite,
                  number.rounded() == number,
                  number >= Double(Int.min),
                  number <= Double(Int.max) else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': every item must be an integer."
                )
            }
            let integer = Int(number)
            guard range.contains(integer) else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': values must be from \(range.lowerBound) through \(range.upperBound)."
                )
            }
            return integer
        }
    }

    static func iso8601(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
