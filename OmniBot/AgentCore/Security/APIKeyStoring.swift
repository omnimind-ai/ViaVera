import Foundation

/// Secret storage boundary used by provider configuration UI and runtime code.
nonisolated public protocol APIKeyStoring: Sendable {
    func saveAPIKey(_ apiKey: String, for providerID: String) throws
    func apiKey(for providerID: String) throws -> String?
    func deleteAPIKey(for providerID: String) throws
    func saveEndpointBinding(_ endpointIdentity: String, for providerID: String) throws
    func endpointBinding(for providerID: String) throws -> String?
    func deleteEndpointBinding(for providerID: String) throws
}
