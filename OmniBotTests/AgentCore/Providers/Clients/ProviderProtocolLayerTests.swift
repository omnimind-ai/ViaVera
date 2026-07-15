import CryptoKit
import Foundation
import Testing

@testable import Via_Vera

@Suite("Provider protocol layer")
struct ProviderProtocolLayerTests {
    @Test("Legacy profiles default to the OpenAI-compatible protocol")
    func legacyProfileDefaultsProtocolType() throws {
        let data = Data(
            #"""
            {
              "id": "legacy-provider",
              "name": "Legacy Provider",
              "baseURL": "https://legacy.example/v1",
              "wireAPI": "chat_completions",
              "defaultHeaders": {},
              "models": [],
              "isEnabled": true
            }
            """#.utf8
        )

        let profile = try JSONDecoder().decode(ProviderProfile.self, from: data)

        #expect(profile.protocolType == .openAICompatible)
        #expect(profile.wireAPI == .chatCompletions)
    }

    @Test("Provider protocol raw values remain persistence compatible")
    func providerProtocolRawValuesAreStable() throws {
        let expected: [(ProviderProtocolType, String)] = [
            (.openAICompatible, "openai_compatible"),
            (.deepSeek, "deepseek"),
            (.anthropic, "anthropic")
        ]

        for (protocolType, rawValue) in expected {
            #expect(protocolType.rawValue == rawValue)
            let encoded = try JSONEncoder().encode(protocolType)
            #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
            #expect(
                try JSONDecoder().decode(ProviderProtocolType.self, from: encoded)
                    == protocolType
            )
        }
    }

    @Test("Anthropic rejects the OpenAI Responses wire API")
    func anthropicRejectsResponsesWireAPI() throws {
        let profile = ProviderProfile(
            id: "anthropic",
            name: "Anthropic",
            baseURL: try #require(URL(string: "https://api.anthropic.com")),
            protocolType: .anthropic,
            wireAPI: .responses
        )

        #expect(
            throws: ProviderStoreError.unsupportedWireAPI(.anthropic, .responses)
        ) {
            try ProviderStore.validate(profile)
        }
    }

    @Test("Endpoint resolver converts root, versioned, and complete provider URLs")
    func endpointResolverNormalizesAllSupportedEndpointShapes() throws {
        let bases = [
            "https://api.example.com",
            "https://api.example.com/v1",
            "https://api.example.com/v1/chat/completions",
            "https://api.example.com/v1/responses",
            "https://api.example.com/v1/messages",
            "https://api.example.com/v1/models"
        ]
        let expectations: [(ProviderEndpointResolver.Endpoint, String)] = [
            (.chatCompletions, "https://api.example.com/v1/chat/completions"),
            (.responses, "https://api.example.com/v1/responses"),
            (.messages, "https://api.example.com/v1/messages"),
            (.models, "https://api.example.com/v1/models")
        ]

        for base in bases {
            let baseURL = try #require(URL(string: base))
            for (endpoint, expectedURL) in expectations {
                #expect(
                    try ProviderEndpointResolver.url(for: baseURL, endpoint: endpoint)
                        .absoluteString == expectedURL,
                    "Failed to convert \(base) to \(expectedURL)"
                )
            }
        }
    }

    @Test("Request endpoint follows the selected provider protocol and wire API")
    func requestEndpointFollowsProtocolAndWireAPI() throws {
        let baseURL = try #require(URL(string: "https://api.example.com"))
        let openAIChat = ProviderProfile(
            name: "OpenAI Chat",
            baseURL: baseURL,
            protocolType: .openAICompatible,
            wireAPI: .chatCompletions
        )
        let openAIResponses = ProviderProfile(
            name: "OpenAI Responses",
            baseURL: baseURL,
            protocolType: .openAICompatible,
            wireAPI: .responses
        )
        let anthropic = ProviderProfile(
            name: "Anthropic",
            baseURL: baseURL,
            protocolType: .anthropic,
            wireAPI: .chatCompletions
        )

        #expect(
            try ProviderEndpointResolver.requestURL(for: openAIChat).absoluteString
                == "https://api.example.com/v1/chat/completions"
        )
        #expect(
            try ProviderEndpointResolver.requestURL(for: openAIResponses).absoluteString
                == "https://api.example.com/v1/responses"
        )
        #expect(
            try ProviderEndpointResolver.requestURL(for: anthropic).absoluteString
                == "https://api.example.com/v1/messages"
        )
    }

    @Test("Credential endpoint identity changes with protocol and wire API")
    func endpointIdentityIncludesProtocolAndWireAPI() throws {
        let baseURL = try #require(URL(string: "https://gateway.example"))
        let openAIChat = ProviderProfile(
            id: "provider",
            name: "Provider",
            baseURL: baseURL,
            protocolType: .openAICompatible,
            wireAPI: .chatCompletions
        )
        let deepSeekChat = ProviderProfile(
            id: openAIChat.id,
            name: openAIChat.name,
            baseURL: baseURL,
            protocolType: .deepSeek,
            wireAPI: .chatCompletions
        )
        let openAIResponses = ProviderProfile(
            id: openAIChat.id,
            name: openAIChat.name,
            baseURL: baseURL,
            protocolType: .openAICompatible,
            wireAPI: .responses
        )

        let chatIdentity = ProviderEndpointIdentity.canonical(for: openAIChat)
        #expect(chatIdentity != ProviderEndpointIdentity.canonical(for: deepSeekChat))
        #expect(chatIdentity != ProviderEndpointIdentity.canonical(for: openAIResponses))

        var completeEndpointProfile = openAIChat
        completeEndpointProfile.baseURL = try #require(
            URL(string: "https://gateway.example/v1/chat/completions")
        )
        #expect(
            chatIdentity == ProviderEndpointIdentity.canonical(for: completeEndpointProfile)
        )
    }

    @Test("Legacy OpenAI Chat credentials keep their existing endpoint identity")
    func legacyOpenAIChatEndpointIdentityRemainsStable() throws {
        let profile = ProviderProfile(
            id: "legacy-provider",
            name: "Legacy Provider",
            baseURL: try #require(URL(string: "https://gateway.example/v1")),
            defaultHeaders: ["X-Tenant": "north"]
        )

        #expect(
            ProviderEndpointIdentity.canonical(for: profile)
                == legacyOpenAIChatIdentity(for: profile)
        )
    }

    private func legacyOpenAIChatIdentity(for profile: ProviderProfile) -> String {
        let endpoint = try? ProviderEndpointResolver.url(
            for: profile.baseURL,
            endpoint: .chatCompletions
        )
        guard var components = URLComponents(
            url: endpoint ?? profile.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            return ""
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        components.fragment = nil
        while components.percentEncodedPath.count > 1,
              components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        let canonicalEndpoint = components.string ?? profile.baseURL.absoluteString
        let unsortedHeaders: [(name: String, value: String)] = profile.defaultHeaders.map {
            (name: $0.key.lowercased(), value: $0.value)
        }
        let headers = unsortedHeaders.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.value < rhs.value
            }
            return lhs.name < rhs.name
        }

        var payload = Data()
        appendLegacy(profile.wireAPI.rawValue, to: &payload)
        appendLegacy(canonicalEndpoint, to: &payload)
        appendLegacy(String(headers.count), to: &payload)
        for header in headers {
            appendLegacy(header.name, to: &payload)
            appendLegacy(header.value, to: &payload)
        }
        return "sha256:\(Data(SHA256.hash(data: payload)).base64EncodedString())"
    }

    private func appendLegacy(_ value: String, to payload: inout Data) {
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        payload.append(bytes)
    }
}
