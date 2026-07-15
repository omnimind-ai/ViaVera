import Foundation

extension OmniAgentToolExecutor {
    func validateCommand(_ command: String, parameterName: String = "command") throws {
        let byteCount = command.utf8.count
        guard byteCount <= limits.maximumCommandBytes else {
            throw OmniAgentToolError(
                "Parameter '\(parameterName)' is \(byteCount) UTF-8 bytes, exceeding the \(limits.maximumCommandBytes)-byte limit."
            )
        }
    }

    func terminalEnvironment(_ arguments: OmniToolArguments) throws -> [String: String] {
        try arguments.stringDictionary(
            "environment",
            maximumEntries: limits.maximumEnvironmentVariables,
            maximumKeyBytes: limits.maximumEnvironmentKeyBytes,
            maximumValueBytes: limits.maximumEnvironmentValueBytes,
            maximumTotalBytes: limits.maximumEnvironmentBytes
        )
    }

    func validateEnvironment(_ environment: [String: String]) throws {
        guard environment.count <= limits.maximumEnvironmentVariables else {
            throw OmniAgentToolError(
                "Environment contains \(environment.count) entries, exceeding the \(limits.maximumEnvironmentVariables)-variable limit."
            )
        }

        var totalBytes = 0
        for (key, value) in environment {
            let keyBytes = key.utf8.count
            let valueBytes = value.utf8.count
            guard keyBytes <= limits.maximumEnvironmentKeyBytes else {
                throw OmniAgentToolError(
                    "Environment key '\(key)' exceeds the \(limits.maximumEnvironmentKeyBytes)-byte UTF-8 limit."
                )
            }
            guard valueBytes <= limits.maximumEnvironmentValueBytes else {
                throw OmniAgentToolError(
                    "Environment value for '\(key)' exceeds the \(limits.maximumEnvironmentValueBytes)-byte UTF-8 limit."
                )
            }
            totalBytes += keyBytes + valueBytes + 2
            guard totalBytes <= limits.maximumEnvironmentBytes else {
                throw OmniAgentToolError(
                    "Environment exceeds the \(limits.maximumEnvironmentBytes)-byte UTF-8 limit."
                )
            }
        }
    }

    func boundedText(_ text: String, maximumCharacters: Int) -> (text: String, truncated: Bool) {
        guard text.count > maximumCharacters else { return (text, false) }
        let suffix = "\n[output truncated at \(maximumCharacters) characters]"
        let prefixCount = max(0, maximumCharacters - suffix.count)
        return (String(text.prefix(prefixCount)) + suffix, true)
    }

    func terminalOutput(
        standardOutput: String,
        standardError: String,
        failureDescription: String?
    ) -> String {
        var sections: [String] = []
        if !standardOutput.isEmpty {
            sections.append(standardOutput)
        }
        if !standardError.isEmpty {
            sections.append("[stderr]\n\(standardError)")
        }
        if let failureDescription, !failureDescription.isEmpty {
            sections.append("[runtime error]\n\(failureDescription)")
        }
        return sections.isEmpty ? "(no output)" : sections.joined(separator: "\n")
    }

    func durationSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
