import Foundation

nonisolated enum ProviderEndpointResolver {
    enum Endpoint: Sendable {
        case chatCompletions
        case responses
        case messages
        case models

        var pathComponents: [String] {
            switch self {
            case .chatCompletions:
                ["chat", "completions"]
            case .responses:
                ["responses"]
            case .messages:
                ["messages"]
            case .models:
                ["models"]
            }
        }
    }

    static func requestURL(for profile: ProviderProfile) throws -> URL {
        switch profile.protocolType {
        case .anthropic:
            try url(for: profile.baseURL, endpoint: .messages)
        case .openAICompatible, .deepSeek:
            switch profile.wireAPI {
            case .chatCompletions:
                try url(for: profile.baseURL, endpoint: .chatCompletions)
            case .responses:
                try url(for: profile.baseURL, endpoint: .responses)
            }
        }
    }

    static func modelsURL(for profile: ProviderProfile) throws -> URL {
        try url(for: profile.baseURL, endpoint: .models)
    }

    static func url(for baseURL: URL, endpoint: Endpoint) throws -> URL {
        guard ProviderStore.isAllowedProviderEndpoint(baseURL),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OpenAICompatibleClientError.invalidBaseURL(baseURL)
        }

        var path = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let normalizedPath = path.map { $0.lowercased() }
        let target = endpoint.pathComponents
        if normalizedPath.suffix(target.count) == target[...] {
            return baseURL
        }

        if normalizedPath.suffix(2) == ["chat", "completions"] {
            path.removeLast(2)
        } else if let last = normalizedPath.last,
                  ["responses", "messages", "models"].contains(last) {
            path.removeLast()
        }

        if path.last?.lowercased() != "v1" {
            path.append("v1")
        }
        path.append(contentsOf: target)
        components.percentEncodedPath = "/" + path
            .map(Self.percentEncodedPathComponent)
            .joined(separator: "/")

        guard let url = components.url else {
            throw OpenAICompatibleClientError.invalidBaseURL(baseURL)
        }
        return url
    }

    private static func percentEncodedPathComponent(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
