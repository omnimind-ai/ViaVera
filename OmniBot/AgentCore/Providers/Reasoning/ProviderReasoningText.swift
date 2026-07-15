import Foundation

nonisolated enum ProviderReasoningText {
    static func first(in values: AgentValue?...) -> String? {
        for value in values {
            if let text = text(from: value), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    static func text(from value: AgentValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(value):
            return value
        case let .array(values):
            return joined(values.compactMap { text(from: $0) })
        case let .object(values):
            return first(in: [
                values["reasoning_content"],
                values["reasoning"],
                values["thinking"],
                values["summary"],
                values["text"],
                values["content"],
            ])
        case .null, .bool, .number:
            return nil
        }
    }

    private static func first(in values: [AgentValue?]) -> String? {
        for value in values {
            if let text = text(from: value), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func joined(_ values: [String]) -> String? {
        let values = values.filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        return values.joined()
    }
}
