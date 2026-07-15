import Foundation
import Testing
@testable import Via_Vera

struct ProviderStoreTests {
    @Test("Bootstrap quarantines an unreadable provider store instead of crashing")
    @MainActor
    func bootstrapQuarantinesCorruptStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "OmniBot-ProviderBootstrap-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "providers.json")
        try Data("{".utf8).write(to: file)

        let recovered = try AppDependencies.recoverProviderStoreIfNeeded(fileURL: file)

        #expect(await recovered.store.profiles().isEmpty)
        #expect(recovered.notice?.contains("已隔离") == true)
        let quarantine = try #require(recovered.quarantineURL)
        #expect(FileManager.default.fileExists(atPath: quarantine.path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func persistsOnlyNonSecretProfiles() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let store = try ProviderStore(fileURL: location)
        let first = ProviderProfile(
            id: "first",
            name: "First",
            baseURL: try #require(URL(string: "https://first.example/v1")),
            defaultHeaders: ["X-Tenant": "tenant-a"]
        )
        let second = ProviderProfile(
            id: "second",
            name: "Second",
            baseURL: try #require(URL(string: "https://second.example/v1"))
        )

        try await store.upsert(first)
        try await store.upsert(second)

        let rawJSON = try String(contentsOf: location, encoding: .utf8)
        #expect(!rawJSON.localizedCaseInsensitiveContains("apiKey"))
        #expect(!rawJSON.localizedCaseInsensitiveContains("authorization"))
        #expect(!rawJSON.contains("selectedProviderID"))

        let reloaded = try ProviderStore(fileURL: location)
        #expect(await reloaded.profiles() == [first, second])
    }

    @Test func rejectsHeadersThatCouldPersistCredentials() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)
        let profile = ProviderProfile(
            id: "unsafe",
            name: "Unsafe",
            baseURL: try #require(URL(string: "https://example.com/v1")),
            defaultHeaders: ["Authorization": "Bearer should-not-be-written"]
        )

        do {
            try await store.upsert(profile)
            Issue.record("Expected secretHeaderNotAllowed")
        } catch let error as ProviderStoreError {
            #expect(error == .secretHeaderNotAllowed("Authorization"))
        }
        #expect(!FileManager.default.fileExists(atPath: location.path))
    }

    @Test func rejectsInsecureRemoteEndpointsAndAllowsLoopbackHTTP() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)

        let remote = ProviderProfile(
            id: "remote",
            name: "Remote",
            baseURL: try #require(URL(string: "http://api.example.com/v1"))
        )
        await #expect(throws: ProviderStoreError.insecureBaseURL) {
            try await store.upsert(remote)
        }

        let loopback = ProviderProfile(
            id: "local",
            name: "Local",
            baseURL: try #require(URL(string: "http://127.0.0.42:8080/v1"))
        )
        try await store.upsert(loopback)
        #expect(await store.profile(id: loopback.id) == loopback)
    }

    @Test func rejectsCredentialsAndSecretsEmbeddedInEndpointOrHeaders() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)

        let userInfo = ProviderProfile(
            id: "userinfo",
            name: "User info",
            baseURL: try #require(URL(string: "https://user:password@example.com/v1"))
        )
        await #expect(throws: ProviderStoreError.baseURLCredentialsNotAllowed) {
            try await store.upsert(userInfo)
        }

        let querySecret = ProviderProfile(
            id: "query",
            name: "Query",
            baseURL: try #require(URL(string: "https://example.com/v1?api_key=secret"))
        )
        await #expect(throws: ProviderStoreError.secretQueryItemNotAllowed("api_key")) {
            try await store.upsert(querySecret)
        }

        let cookie = ProviderProfile(
            id: "cookie",
            name: "Cookie",
            baseURL: try #require(URL(string: "https://example.com/v1")),
            defaultHeaders: ["Cookie": "session=secret"]
        )
        await #expect(throws: ProviderStoreError.secretHeaderNotAllowed("Cookie")) {
            try await store.upsert(cookie)
        }
    }

    @Test func rejectsSecretNameAliasesAcrossQueriesAndHeaders() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)

        let queryAliases = ["auth", "x_auth", "access_key", "privateKey", "x-amz-signature"]
        for (index, alias) in queryAliases.enumerated() {
            let profile = ProviderProfile(
                id: "query-alias-\(index)",
                name: "Query Alias \(index)",
                baseURL: try #require(
                    URL(string: "https://example.com/v1?\(alias)=must-not-persist")
                )
            )
            await #expect(throws: ProviderStoreError.secretQueryItemNotAllowed(alias)) {
                try await store.upsert(profile)
            }
        }

        let headerAliases = ["X-Auth", "Access_Key", "Private-Key", "X-Amz-Signature"]
        for (index, alias) in headerAliases.enumerated() {
            let profile = ProviderProfile(
                id: "header-alias-\(index)",
                name: "Header Alias \(index)",
                baseURL: try #require(URL(string: "https://example.com/v1")),
                defaultHeaders: [alias: "must-not-persist"]
            )
            await #expect(throws: ProviderStoreError.secretHeaderNotAllowed(alias)) {
                try await store.upsert(profile)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: location.path))
    }

    @Test func rejectsAmbiguousInvalidAndRoutingHeaders() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)
        let url = try #require(URL(string: "https://example.com/v1"))

        let duplicate = ProviderProfile(
            id: "duplicate-header",
            name: "Duplicate header",
            baseURL: url,
            defaultHeaders: ["X-Tenant": "tenant-a", "x-tenant": "tenant-b"]
        )
        await #expect(throws: ProviderStoreError.duplicateHeaderName("x-tenant")) {
            try await store.upsert(duplicate)
        }

        let routingHeaders = [
            "Host",
            "Forwarded",
            "X-Forwarded-Host",
            "X-Forwarded-Proto",
            "X-Forwarded-Port"
        ]
        for (index, header) in routingHeaders.enumerated() {
            let profile = ProviderProfile(
                id: "routing-\(index)",
                name: "Routing \(index)",
                baseURL: url,
                defaultHeaders: [header: "attacker.example"]
            )
            await #expect(throws: ProviderStoreError.routingHeaderNotAllowed(header)) {
                try await store.upsert(profile)
            }
        }

        let invalidName = ProviderProfile(
            id: "invalid-header-name",
            name: "Invalid header name",
            baseURL: url,
            defaultHeaders: ["Bad Header": "value"]
        )
        await #expect(throws: ProviderStoreError.invalidHeaderName("Bad Header")) {
            try await store.upsert(invalidName)
        }

        let invalidValue = ProviderProfile(
            id: "invalid-header-value",
            name: "Invalid header value",
            baseURL: url,
            defaultHeaders: ["X-Tenant": "tenant-a\r\nHost: attacker.example"]
        )
        await #expect(throws: ProviderStoreError.invalidHeaderValue("X-Tenant")) {
            try await store.upsert(invalidValue)
        }
    }

    @Test func rejectsNonemptyEndpointFragments() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)
        let profile = ProviderProfile(
            id: "fragment",
            name: "Fragment",
            baseURL: try #require(URL(string: "https://example.com/v1#api_key=must-not-persist"))
        )

        await #expect(throws: ProviderStoreError.baseURLFragmentNotAllowed) {
            try await store.upsert(profile)
        }
        #expect(!FileManager.default.fileExists(atPath: location.path))
        #expect(!ProviderStore.isAllowedProviderEndpoint(profile.baseURL))
    }

    @Test func rejectsUntrimmedIdentifiersAndInvalidModelLimits() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)
        let url = try #require(URL(string: "https://example.com/v1"))

        await #expect(throws: ProviderStoreError.invalidIdentifier) {
            try await store.upsert(ProviderProfile(id: " provider ", name: "Bad", baseURL: url))
        }

        let invalidLimits = ProviderProfile(
            id: "limits",
            name: "Limits",
            baseURL: url,
            models: [ModelOption(id: "model", contextWindow: 4_096, maxOutputTokens: 8_192)]
        )
        await #expect(throws: ProviderStoreError.invalidModelLimits("model")) {
            try await store.upsert(invalidLimits)
        }
    }

    @Test func rejectsDuplicateProviderIdentifiersInPersistedState() throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let profile = ProviderProfile(
            id: "duplicate",
            name: "Duplicate",
            baseURL: try #require(URL(string: "https://example.com/v1"))
        )
        let fixture = PersistedProviderFixture(
            schemaVersion: 1,
            profiles: [profile, profile]
        )
        try JSONEncoder().encode(fixture).write(to: location)

        #expect(throws: ProviderStoreError.duplicateProviderIdentifier(profile.id)) {
            _ = try ProviderStore(fileURL: location)
        }
    }

    @Test func rejectsOversizedAndNonregularStoreFilesBeforeDecoding() throws {
        let oversizedLocation = try temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(
                at: oversizedLocation.deletingLastPathComponent()
            )
        }
        try Data(
            repeating: 0x20,
            count: ProviderStore.maximumStoreByteCount + 1
        ).write(to: oversizedLocation)

        #expect(
            throws: ProviderStoreError.storeFileTooLarge(
                ProviderStore.maximumStoreByteCount
            )
        ) {
            _ = try ProviderStore(fileURL: oversizedLocation)
        }

        let symlinkLocation = try temporaryStoreURL()
        defer {
            try? FileManager.default.removeItem(
                at: symlinkLocation.deletingLastPathComponent()
            )
        }
        let target = symlinkLocation.deletingLastPathComponent()
            .appendingPathComponent("real-providers.json")
        let emptyFixture = PersistedProviderFixture(
            schemaVersion: 1,
            profiles: []
        )
        try JSONEncoder().encode(emptyFixture).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: symlinkLocation,
            withDestinationURL: target
        )

        #expect(throws: ProviderStoreError.storeFileNotRegular) {
            _ = try ProviderStore(fileURL: symlinkLocation)
        }
    }

    @Test func enforcesMetadataCountsAndUTF8FieldLimits() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)
        let url = try #require(URL(string: "https://example.com/v1"))

        let tooManyModels = ProviderProfile(
            id: "too-many-models",
            name: "Too many models",
            baseURL: url,
            models: (0...ProviderStore.maximumModelsPerProvider).map {
                ModelOption(id: "model-\($0)")
            }
        )
        await #expect(
            throws: ProviderStoreError.metadataLimitExceeded(
                "provider contains more than \(ProviderStore.maximumModelsPerProvider) models"
            )
        ) {
            try await store.upsert(tooManyModels)
        }

        var tooManyHeaderValues: [String: String] = [:]
        for index in 0...ProviderStore.maximumHeadersPerProvider {
            tooManyHeaderValues["X-Metadata-\(index)"] = "value"
        }
        let tooManyHeaders = ProviderProfile(
            id: "too-many-headers",
            name: "Too many headers",
            baseURL: url,
            defaultHeaders: tooManyHeaderValues
        )
        await #expect(
            throws: ProviderStoreError.metadataLimitExceeded(
                "provider contains more than \(ProviderStore.maximumHeadersPerProvider) default headers"
            )
        ) {
            try await store.upsert(tooManyHeaders)
        }

        let longIdentifier = String(
            repeating: "a",
            count: ProviderStore.maximumProviderIdentifierByteCount + 1
        )
        await #expect(
            throws: ProviderStoreError.metadataLimitExceeded(
                "provider identifier exceeds \(ProviderStore.maximumProviderIdentifierByteCount) UTF-8 bytes"
            )
        ) {
            try await store.upsert(
                ProviderProfile(id: longIdentifier, name: "Long", baseURL: url)
            )
        }

        let profiles = (0...ProviderStore.maximumProviderCount).map { index in
            ProviderProfile(
                id: "provider-\(index)",
                name: "Provider \(index)",
                baseURL: url
            )
        }
        let fixture = PersistedProviderFixture(
            schemaVersion: 1,
            profiles: profiles
        )
        try JSONEncoder().encode(fixture).write(to: location)
        #expect(
            throws: ProviderStoreError.metadataLimitExceeded(
                "store contains more than \(ProviderStore.maximumProviderCount) providers"
            )
        ) {
            _ = try ProviderStore(fileURL: location)
        }
    }

    @Test func removalPreservesTheRemainingProviders() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)
        let url = try #require(URL(string: "https://example.com/v1"))

        try await store.upsert(ProviderProfile(id: "one", name: "One", baseURL: url))
        try await store.upsert(ProviderProfile(id: "two", name: "Two", baseURL: url))
        try await store.remove(id: "two")

        #expect(await store.profiles().map(\.id) == ["one"])
    }

    @Test func persistsProviderOrder() async throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try ProviderStore(fileURL: location)
        let url = try #require(URL(string: "https://example.com/v1"))

        for identifier in ["one", "two", "three"] {
            try await store.upsert(
                ProviderProfile(id: identifier, name: identifier, baseURL: url)
            )
        }
        try await store.reorder(providerIDs: ["three", "one", "two"])

        #expect(await store.profiles().map(\.id) == ["three", "one", "two"])
        let reloaded = try ProviderStore(fileURL: location)
        #expect(await reloaded.profiles().map(\.id) == ["three", "one", "two"])
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("providers.json")
    }
}

private struct PersistedProviderFixture: Encodable {
    let schemaVersion: Int
    let profiles: [ProviderProfile]
}
