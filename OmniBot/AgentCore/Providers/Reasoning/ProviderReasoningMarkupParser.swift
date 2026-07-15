import Foundation

nonisolated enum ProviderReasoningMarkupParser {
    struct Result: Equatable, Sendable {
        let content: String
        let reasoning: String
    }

    static func parse(_ value: String, isFinal: Bool = true) -> Result {
        let openingTag = "<think>"
        let closingTag = "</think>"
        var remainder = value[...]
        var content = ""
        var reasoning = ""
        var isThinking = false

        while !remainder.isEmpty {
            // Some OpenAI-compatible models omit the opening tag but still
            // terminate their private reasoning with </think>. Match the
            // Android accumulator's safety rule: before any visible answer,
            // treat the prefix of an orphan closing tag as reasoning instead
            // of leaking it into assistant content.
            if !isThinking,
               content.isEmpty,
               let closingRange = remainder.range(of: closingTag, options: .caseInsensitive),
               remainder.range(of: openingTag, options: .caseInsensitive)
                   .map({ closingRange.lowerBound < $0.lowerBound }) ?? true {
                reasoning += String(remainder[..<closingRange.lowerBound])
                remainder = remainder[closingRange.upperBound...]
                continue
            }

            let target = isThinking ? closingTag : openingTag
            if let range = remainder.range(of: target, options: .caseInsensitive) {
                append(
                    String(remainder[..<range.lowerBound]),
                    isThinking: isThinking,
                    content: &content,
                    reasoning: &reasoning
                )
                remainder = remainder[range.upperBound...]
                isThinking.toggle()
                continue
            }

            let tail = String(remainder)
            let heldCharacterCount = isFinal
                ? 0
                : trailingTagPrefixLength(in: tail, tag: target)
            let visible = heldCharacterCount == 0
                ? tail
                : String(tail.dropLast(heldCharacterCount))
            append(
                visible,
                isThinking: isThinking,
                content: &content,
                reasoning: &reasoning
            )
            break
        }

        return Result(content: content, reasoning: reasoning)
    }

    private static func append(
        _ value: String,
        isThinking: Bool,
        content: inout String,
        reasoning: inout String
    ) {
        if isThinking {
            reasoning += value
        } else {
            content += value
        }
    }

    private static func trailingTagPrefixLength(in value: String, tag: String) -> Int {
        let maximum = min(value.count, tag.count - 1)
        guard maximum > 0 else { return 0 }
        for count in stride(from: maximum, through: 1, by: -1) {
            if value.suffix(count).lowercased() == tag.prefix(count).lowercased() {
                return count
            }
        }
        return 0
    }
}
