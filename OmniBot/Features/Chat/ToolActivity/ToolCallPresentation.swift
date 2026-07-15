import Foundation

struct ToolCallPresentation: Identifiable, Hashable {
    let id: String
    let callID: String
    let assistantMessageID: UUID
    let callIndex: Int
    let name: String
    let title: String
    let symbolName: String
    let typeLabel: String
    let status: ToolCallStatus
    let arguments: String
    let command: String?
    let workingDirectory: String?
    let output: String
    let metadata: String
    let isTerminal: Bool
    let isBrowser: Bool
    let browserTitle: String?
    let browserURL: String?
    let wasStarted: Bool

    init(
        assistantMessageID: UUID,
        callIndex: Int,
        call: AgentToolCall,
        result: MessageRecord?,
        runIsActive: Bool,
        activeCallID: String?,
        liveTerminalOutput: String?
    ) {
        let argumentObject = Self.decodeObject(call.arguments)
        let resultEnvelope = Self.decodeObject(result?.content)
        let resultMetadata = resultEnvelope?["metadata"]?.objectValue
        let argumentTitle = argumentObject?["tool_title"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadataTitle = resultMetadata?["toolTitle"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        id = "\(assistantMessageID.uuidString):\(callIndex)"
        callID = call.id
        self.assistantMessageID = assistantMessageID
        self.callIndex = callIndex
        name = call.name
        title = Self.firstNonEmpty(argumentTitle, metadataTitle, call.name)
        symbolName = Self.symbolName(for: call.name)
        typeLabel = Self.typeLabel(for: call.name)
        arguments = Self.prettyJSON(call.arguments)
        command = argumentObject?["command"]?.stringValue
        workingDirectory = argumentObject?["working_directory"]?.stringValue
            ?? resultMetadata?["workingDirectory"]?.stringValue
        isTerminal = call.name.hasPrefix("terminal_")
        isBrowser = call.name == "browser_use"
        browserTitle = Self.firstNonEmptyOptional(
            resultMetadata?["title"]?.stringValue,
            argumentTitle
        )
        browserURL = Self.firstNonEmptyOptional(
            resultMetadata?["url"]?.stringValue,
            argumentObject?["url"]?.stringValue
        )
        wasStarted = result != nil || (runIsActive && activeCallID == call.id)

        let resultContent = resultEnvelope?["content"]?.stringValue
            ?? result?.content
            ?? ""
        let normalizedLiveOutput = liveTerminalOutput?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        output = normalizedLiveOutput.isEmpty ? resultContent : normalizedLiveOutput
        metadata = Self.prettyJSON(resultMetadata)

        if let result {
            let reportedSuccess = resultEnvelope?["success"]?.boolValue
            let wasInterrupted = resultMetadata?["interrupted"]?.boolValue == true
            if wasInterrupted {
                status = .interrupted
            } else {
                status = result.status == .failed || reportedSuccess == false
                    ? .failed
                    : .succeeded
            }
        } else if runIsActive {
            status = activeCallID == call.id ? .running : .pending
        } else {
            status = .interrupted
        }
    }

    var terminalTranscript: String {
        var sections: [String] = []
        if let command, !command.isEmpty {
            sections.append("$ \(command)")
        }
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOutput.isEmpty {
            sections.append(trimmedOutput)
        } else if status == .running || status == .pending {
            sections.append(status == .running ? "正在等待终端输出…" : "等待执行…")
        } else {
            sections.append("没有输出")
        }
        return sections.joined(separator: "\n")
    }

    private static func decodeObject(_ value: String?) -> [String: AgentValue]? {
        guard let value, !value.isEmpty,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AgentValue.self, from: data) else {
            return nil
        }
        return decoded.objectValue
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !normalized.isEmpty {
                return normalized
            }
        }
        return "工具调用"
    }

    private static func firstNonEmptyOptional(_ values: String?...) -> String? {
        for value in values {
            let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private static func prettyJSON(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return value
        }
        return String(decoding: prettyData, as: UTF8.self)
    }

    private static func prettyJSON(_ value: [String: AgentValue]?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(AgentValue.object(value)) else {
            return ""
        }
        return prettyJSON(String(decoding: data, as: UTF8.self))
    }

    private static func symbolName(for toolName: String) -> String {
        if toolName.hasPrefix("terminal_") {
            return "terminal"
        }
        if toolName.hasPrefix("file_") {
            return "doc.text"
        }
        if toolName.hasPrefix("memory_") {
            return "brain.head.profile"
        }
        if toolName == "browser_use" {
            return "safari"
        }
        return "wrench.and.screwdriver"
    }

    private static func typeLabel(for toolName: String) -> String {
        if toolName.hasPrefix("terminal_") {
            return "终端"
        }
        if toolName.hasPrefix("file_") {
            return "文件"
        }
        if toolName.hasPrefix("memory_") {
            return "记忆"
        }
        if toolName == "browser_use" {
            return "浏览器"
        }
        return "工具"
    }
}

private extension AgentValue {
    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}
