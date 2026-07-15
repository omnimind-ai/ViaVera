import Foundation
import Testing
@testable import Via_Vera

struct KeychainAPIKeyStoreTests {
    @Test func validatesInputsBeforeCallingSecurityFramework() throws {
        let store = KeychainAPIKeyStore(service: "OmniBot.tests.\(UUID().uuidString)")

        do {
            try store.saveAPIKey("valid", for: "   ")
            Issue.record("Expected invalidProviderIdentifier")
        } catch let error as KeychainAPIKeyStoreError {
            #expect(error == .invalidProviderIdentifier)
        }

        do {
            try store.saveAPIKey(" \n ", for: "provider")
            Issue.record("Expected emptyAPIKey")
        } catch let error as KeychainAPIKeyStoreError {
            #expect(error == .emptyAPIKey)
        }

        do {
            try store.saveEndpointBinding(" \n ", for: "provider")
            Issue.record("Expected emptyEndpointBinding")
        } catch let error as KeychainAPIKeyStoreError {
            #expect(error == .emptyEndpointBinding)
        }
    }
}
