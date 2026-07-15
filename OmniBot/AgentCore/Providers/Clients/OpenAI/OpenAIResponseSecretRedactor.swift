import Foundation

/// Removes credentials from provider-controlled text before it can reach UI or
/// persistent conversation error state.
nonisolated enum OpenAIResponseSecretRedactor {
    static let replacement = "[REDACTED]"

    static func containsCredentialVariant(in text: String, apiKey: String) -> Bool {
        literalVariants(for: apiKey).contains { variant in
            !variant.isEmpty && text.contains(variant)
        }
    }

    /// Tool arguments are themselves JSON embedded inside the provider JSON.
    /// Decode that inner layer so `\uXXXX` escapes cannot hide a credential
    /// until after the executable tool payload passes this guard.
    static func containsCredentialVariantInJSON(_ text: String, apiKey: String) -> Bool {
        if containsCredentialVariant(in: text, apiKey: apiKey) {
            return true
        }
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
              ) else {
            return false
        }
        return containsCredentialVariant(inJSONValue: value, apiKey: apiKey)
    }

    static func redact(_ text: String, apiKey: String) -> String {
        var result = text

        // Exact replacement is authoritative for the credential used by this
        // request. Include common wire encodings because raw JSON and URL-like
        // error text may not contain the literal spelling.
        let variants = literalVariants(for: apiKey)
            .filter { !$0.isEmpty && $0 != replacement }
            .sorted { $0.count > $1.count }
        for variant in variants {
            result = result.replacingOccurrences(of: variant, with: replacement)
        }

        // Also cover conventional credential labels in case a provider echoes
        // a derived or differently formatted token rather than the exact key.
        let patterns = [
            #"(?i)(\bbearer[\t ]+[\"']?)(?!\[REDACTED\])[^\s\"',;}\]\)]+"#,
            #"(?i)([\"']?\b(?:api[\s_-]*key|access[\s_-]*token|auth[\s_-]*token|authorization|credential|secret|token)\b[\"']?\s*(?::|=)\s*[\"']?)(?!\[REDACTED\])[^\"'\s,;}&\]]+"#,
            #"(?i)(\b(?:api[\s_-]*key|access[\s_-]*token|auth[\s_-]*token|secret|token)\b[\t ]+(?:is[\t ]+)?)(?=[A-Za-z0-9._~+/\-=]*[-._~+/\=0-9])([A-Za-z0-9][A-Za-z0-9._~+/\-=]{5,})"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1\(replacement)"
            )
        }
        return result
    }

    /// Redacts a growing response while retaining only a suffix that might be
    /// the beginning of a credential split across two SSE chunks.
    static func redactStreamingSnapshot(_ text: String, apiKey: String) -> String {
        let variants = literalVariants(for: apiKey).filter { !$0.isEmpty }
        var retainedCount = 0

        for variant in variants {
            let maximumCandidate = min(text.count, max(0, variant.count - 1))
            guard maximumCandidate > retainedCount else { continue }
            for candidate in stride(from: maximumCandidate, through: retainedCount + 1, by: -1) {
                if text.suffix(candidate) == variant.prefix(candidate) {
                    retainedCount = candidate
                    break
                }
            }
        }

        let safeText = retainedCount > 0 ? String(text.dropLast(retainedCount)) : text
        return redact(safeText, apiKey: apiKey)
    }

    private static func literalVariants(for apiKey: String) -> Set<String> {
        var variants: Set<String> = [apiKey]
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            variants.insert(trimmed)
        }

        for value in Array(variants) where !value.isEmpty {
            for withoutEscapingSlashes in [false, true] {
                let encoder = JSONEncoder()
                if withoutEscapingSlashes {
                    encoder.outputFormatting = [.withoutEscapingSlashes]
                }
                if let encoded = try? encoder.encode(value),
                   var jsonLiteral = String(data: encoded, encoding: .utf8),
                   jsonLiteral.count >= 2 {
                    jsonLiteral.removeFirst()
                    jsonLiteral.removeLast()
                    variants.insert(jsonLiteral)
                }
            }

            var unreserved = CharacterSet.alphanumerics
            unreserved.insert(charactersIn: "-._~")
            for allowedCharacters in [CharacterSet.alphanumerics, unreserved] {
                if let percentEncoded = value.addingPercentEncoding(
                    withAllowedCharacters: allowedCharacters
                ) {
                    variants.insert(percentEncoded)
                    variants.insert(lowercasingPercentEscapes(in: percentEncoded))
                }
            }
        }
        return variants
    }

    private static func containsCredentialVariant(
        inJSONValue value: Any,
        apiKey: String
    ) -> Bool {
        if let string = value as? String {
            return containsCredentialVariant(in: string, apiKey: apiKey)
        }
        if let array = value as? [Any] {
            return array.contains {
                containsCredentialVariant(inJSONValue: $0, apiKey: apiKey)
            }
        }
        if let object = value as? [String: Any] {
            return object.contains { key, value in
                containsCredentialVariant(in: key, apiKey: apiKey)
                    || containsCredentialVariant(inJSONValue: value, apiKey: apiKey)
            }
        }
        return false
    }

    private static func lowercasingPercentEscapes(in value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            result.append(character)
            index = value.index(after: index)
            guard character == "%" else { continue }
            for _ in 0..<2 where index < value.endIndex {
                result.append(contentsOf: value[index].lowercased())
                index = value.index(after: index)
            }
        }
        return result
    }
}
