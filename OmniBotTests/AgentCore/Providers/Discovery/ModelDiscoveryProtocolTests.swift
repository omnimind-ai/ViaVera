import Foundation
import Testing

@testable import Via_Vera

@Suite("Provider-specific model discovery", .serialized)
struct ModelDiscoveryProtocolTests {
    @Test("Anthropic model discovery uses Messages API authentication and model path")
    func anthropicModelDiscoveryRequest() async throws {
        AnthropicModelDiscoveryURLProtocol.reset()
        defer { AnthropicModelDiscoveryURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnthropicModelDiscoveryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let service = ModelDiscoveryService(
            session: session,
            catalogURL: try #require(URL(string: "https://catalog.example/api.json"))
        )
        let profile = ProviderProfile(
            id: "anthropic",
            name: "Anthropic",
            baseURL: try #require(
                URL(string: "https://api.anthropic.com/v1/messages")
            ),
            protocolType: .anthropic,
            wireAPI: .chatCompletions
        )

        let result = try await service.discoverModels(
            for: profile,
            apiKey: "anthropic-secret"
        )
        let request = try #require(AnthropicModelDiscoveryURLProtocol.providerRequest())

        #expect(result.models.map(\.id) == ["claude-test"])
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

nonisolated private final class AnthropicModelDiscoveryURLProtocol: URLProtocol,
    @unchecked Sendable
{
    private static let lock = NSLock()
    nonisolated(unsafe) private static var capturedProviderRequest: URLRequest?

    static func reset() {
        lock.lock()
        capturedProviderRequest = nil
        lock.unlock()
    }

    static func providerRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedProviderRequest
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let data: Data
        if url.host == "api.anthropic.com" {
            Self.lock.lock()
            Self.capturedProviderRequest = request
            Self.lock.unlock()
            data = Data(
                #"""
                {"data":[{"id":"claude-test","owned_by":"anthropic"}]}
                """#.utf8
            )
        } else {
            data = Data("{}".utf8)
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
