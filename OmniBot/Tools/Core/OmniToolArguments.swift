import Foundation

nonisolated struct OmniToolArguments: Sendable {
    let values: [String: AgentValue]
    let toolTitle: String

    init(call: AgentToolCall) throws {
        let decoded: AgentValue
        do {
            decoded = try call.decodedArguments()
        } catch {
            throw OmniAgentToolError(
                "Invalid JSON arguments for \(call.name): \(error.localizedDescription)"
            )
        }

        guard case let .object(values) = decoded else {
            throw OmniAgentToolError(
                "Invalid arguments for \(call.name): expected a JSON object."
            )
        }
        self.values = values

        guard let titleValue = values["tool_title"] else {
            throw OmniAgentToolError(
                "Missing required parameter 'tool_title' for \(call.name)."
            )
        }
        guard case let .string(title) = titleValue,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OmniAgentToolError(
                "Invalid parameter 'tool_title' for \(call.name): expected a non-empty string."
            )
        }
        guard title.count <= 160 else {
            throw OmniAgentToolError(
                "Invalid parameter 'tool_title' for \(call.name): exceeds the 160-character limit."
            )
        }
        toolTitle = title
    }

    func requiredString(
        _ name: String,
        maximumLength: Int? = nil
    ) throws -> String {
        guard let value = values[name] else {
            throw OmniAgentToolError("Missing required parameter '\(name)'.")
        }
        guard case let .string(string) = value else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected a string."
            )
        }
        if let maximumLength, string.count > maximumLength {
            throw OmniAgentToolError(
                "Parameter '\(name)' exceeds the \(maximumLength)-character limit."
            )
        }
        return string
    }

    func optionalString(
        _ name: String,
        default defaultValue: String? = nil,
        maximumLength: Int? = nil
    ) throws -> String? {
        guard let value = values[name], value != .null else { return defaultValue }
        guard case let .string(string) = value else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected a string."
            )
        }
        if let maximumLength, string.count > maximumLength {
            throw OmniAgentToolError(
                "Parameter '\(name)' exceeds the \(maximumLength)-character limit."
            )
        }
        return string
    }

    func bool(_ name: String, default defaultValue: Bool) throws -> Bool {
        guard let value = values[name], value != .null else { return defaultValue }
        guard case let .bool(result) = value else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected a boolean."
            )
        }
        return result
    }

    func integer(
        _ name: String,
        default defaultValue: Int? = nil,
        range: ClosedRange<Int>? = nil
    ) throws -> Int? {
        guard let value = values[name], value != .null else { return defaultValue }
        guard case let .number(number) = value,
              number.isFinite,
              number.rounded() == number,
              number >= Double(Int.min),
              number <= Double(Int.max) else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected an integer."
            )
        }
        let result = Int(number)
        if let range, !range.contains(result) {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected a value from \(range.lowerBound) through \(range.upperBound)."
            )
        }
        return result
    }

    func stringDictionary(_ name: String) throws -> [String: String] {
        guard let value = values[name], value != .null else { return [:] }
        guard case let .object(object) = value else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': expected an object with string values."
            )
        }

        var result: [String: String] = [:]
        for (key, value) in object {
            guard !key.isEmpty,
                  !key.contains("="),
                  !key.contains("\0"),
                  case let .string(string) = value,
                  !string.contains("\0") else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': environment keys and values must be NUL-free strings, and keys cannot contain '='."
                )
            }
            result[key] = string
        }
        return result
    }

    func stringDictionary(
        _ name: String,
        maximumEntries: Int,
        maximumKeyBytes: Int,
        maximumValueBytes: Int,
        maximumTotalBytes: Int
    ) throws -> [String: String] {
        let result = try stringDictionary(name)
        guard result.count <= maximumEntries else {
            throw OmniAgentToolError(
                "Invalid parameter '\(name)': contains \(result.count) entries, exceeding the \(maximumEntries)-variable limit."
            )
        }

        var totalBytes = 0
        for (key, value) in result {
            let keyBytes = key.utf8.count
            let valueBytes = value.utf8.count
            guard keyBytes <= maximumKeyBytes else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': environment key '\(key)' exceeds the \(maximumKeyBytes)-byte UTF-8 limit."
                )
            }
            guard valueBytes <= maximumValueBytes else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': value for '\(key)' exceeds the \(maximumValueBytes)-byte UTF-8 limit."
                )
            }
            // Environment blocks contain KEY=VALUE plus a terminating NUL.
            totalBytes += keyBytes + valueBytes + 2
            guard totalBytes <= maximumTotalBytes else {
                throw OmniAgentToolError(
                    "Invalid parameter '\(name)': environment exceeds the \(maximumTotalBytes)-byte UTF-8 limit."
                )
            }
        }
        return result
    }
}
