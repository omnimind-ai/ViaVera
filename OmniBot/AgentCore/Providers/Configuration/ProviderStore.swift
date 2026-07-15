import Darwin
import Foundation

/// Storage boundary used by provider settings orchestration.
///
/// The async requirements let tests and alternate stores suspend at precise
/// persistence points while `ProviderStore` continues to satisfy them through
/// its actor-isolated methods.
protocol ProviderStoring: Sendable {
    func profiles() async -> [ProviderProfile]
    func profile(id: String) async -> ProviderProfile?
    func upsert(_ profile: ProviderProfile) async throws
    func remove(id: String) async throws
    func reorder(providerIDs: [String]) async throws
}

/// Actor-isolated persistence for provider metadata.
///
/// `ProviderProfile` has no API-key field. In addition, headers commonly used
/// for credentials are rejected before any JSON is written.
public actor ProviderStore {
    static let maximumStoreByteCount = 1_048_576
    static let maximumProviderCount = 64
    static let maximumModelsPerProvider = 128
    static let maximumHeadersPerProvider = 64
    static let maximumTotalModelCount = 512
    static let maximumTotalHeaderCount = 512
    static let maximumProviderIdentifierByteCount = 128
    static let maximumProviderNameByteCount = 256
    static let maximumBaseURLByteCount = 4_096
    static let maximumModelIdentifierByteCount = 256
    static let maximumModelDisplayNameByteCount = 256
    static let maximumModelProviderNameByteCount = 256
    static let maximumModelDescriptionByteCount = 4_096
    static let maximumModelModalityCount = 16
    static let maximumModelModalityByteCount = 64
    static let maximumHeaderNameByteCount = 128
    static let maximumHeaderValueByteCount = 4_096

    nonisolated private struct PersistedState: Codable, Equatable, Sendable {
        static let currentSchemaVersion = 1

        var schemaVersion: Int
        var profiles: [ProviderProfile]
    }

    public nonisolated let fileURL: URL

    private var state: PersistedState

    public init(fileURL: URL? = nil) throws {
        let resolvedURL = fileURL ?? Self.defaultStoreURL()
        self.fileURL = resolvedURL

        do {
            guard let data = try Self.readPersistedDataIfPresent(from: resolvedURL) else {
                state = Self.emptyState()
                return
            }
            let decoded = try Self.makeDecoder().decode(PersistedState.self, from: data)
            state = try Self.validatedState(decoded)
        } catch let error as ProviderStoreError {
            throw error
        } catch {
            throw ProviderStoreError.corruptedStore(error.localizedDescription)
        }
    }

    public func profiles() -> [ProviderProfile] {
        state.profiles
    }

    public func profile(id: String) -> ProviderProfile? {
        state.profiles.first { $0.id == id }
    }

    public func upsert(_ profile: ProviderProfile) throws {
        let profile = try Self.validated(profile)
        var next = state

        if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) {
            next.profiles[index] = profile
        } else {
            next.profiles.append(profile)
        }

        try persistAndCommit(next)
    }

    public func remove(id: String) throws {
        var next = state
        guard let index = next.profiles.firstIndex(where: { $0.id == id }) else {
            throw ProviderStoreError.providerNotFound(id)
        }
        next.profiles.remove(at: index)
        try persistAndCommit(next)
    }

    public func reorder(providerIDs: [String]) throws {
        let currentIDs = state.profiles.map(\.id)
        guard providerIDs.count == currentIDs.count,
              Set(providerIDs).count == providerIDs.count,
              Set(providerIDs) == Set(currentIDs) else {
            throw ProviderStoreError.invalidProviderOrder
        }

        let profilesByID = Dictionary(uniqueKeysWithValues: state.profiles.map { ($0.id, $0) })
        var next = state
        next.profiles = try providerIDs.map { providerID in
            guard let profile = profilesByID[providerID] else {
                throw ProviderStoreError.invalidProviderOrder
            }
            return profile
        }
        try persistAndCommit(next)
    }

    public func reload() throws {
        do {
            guard let data = try Self.readPersistedDataIfPresent(from: fileURL) else {
                state = Self.emptyState()
                return
            }
            let decoded = try Self.makeDecoder().decode(PersistedState.self, from: data)
            state = try Self.validatedState(decoded)
        } catch let error as ProviderStoreError {
            throw error
        } catch {
            throw ProviderStoreError.corruptedStore(error.localizedDescription)
        }
    }

    public func removeAll() throws {
        try persistAndCommit(Self.emptyState())
    }

    public nonisolated static func defaultStoreURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "OmniBot"
        return baseURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("providers.json", isDirectory: false)
    }

    public nonisolated static func isSensitiveHeaderName(_ name: String) -> Bool {
        let normalized = normalizedSecretName(name)
        let compact = normalized.replacingOccurrences(of: "-", with: "")
        let words = Set(normalized.split(separator: "-").map(String.init))

        let exactNames: Set<String> = [
            "auth",
            "authorization",
            "authentication",
            "proxy-authorization",
            "key",
            "api-key",
            "x-api-key",
            "access-key",
            "private-key",
            "x-auth",
            "x-auth-token",
            "access-token",
            "refresh-token",
            "id-token",
            "cookie",
            "set-cookie",
            "x-amz-signature"
        ]
        if exactNames.contains(normalized) {
            return true
        }

        let sensitiveWords: Set<String> = [
            "auth",
            "authorization",
            "authentication",
            "cookie",
            "credential",
            "credentials",
            "passwd",
            "password",
            "secret",
            "sig",
            "signature",
            "token"
        ]
        if !words.isDisjoint(with: sensitiveWords) {
            return true
        }
        if words.contains("key"),
           !words.isDisjoint(with: ["api", "access", "private", "auth", "secret", "signing"]) {
            return true
        }

        let compactAliases: Set<String> = [
            "auth",
            "xauth",
            "oauth",
            "apikey",
            "xapikey",
            "accesskey",
            "privatekey",
            "secretkey",
            "authkey",
            "authtoken",
            "xauthtoken",
            "accesstoken",
            "refreshtoken",
            "idtoken",
            "xamzsignature"
        ]
        if compactAliases.contains(compact) {
            return true
        }
        return compact.contains("authorization")
            || compact.contains("authentication")
            || compact.contains("apikey")
            || compact.contains("cookie")
            || compact.contains("credential")
            || compact.contains("password")
            || compact.contains("secret")
            || compact.contains("signature")
            || compact.contains("token")
    }

    /// Performs the same validation used by `upsert` without mutating storage.
    /// Callers that coordinate secrets with profile persistence use this as a
    /// preflight before changing the canonical Keychain account.
    nonisolated static func validate(_ profile: ProviderProfile) throws {
        _ = try validated(profile)
    }

    nonisolated static func isAllowedProviderEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.fragment?.isEmpty != false,
              scheme == "https" || (scheme == "http" && isLoopbackHost(host)) else {
            return false
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains(where: { isSensitiveQueryItemName($0.name) }) != true
    }

    private func persistAndCommit(_ next: PersistedState) throws {
        do {
            let next = try Self.validatedState(next)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try Self.makeEncoder().encode(next)
            guard data.count <= Self.maximumStoreByteCount else {
                throw ProviderStoreError.storeFileTooLarge(Self.maximumStoreByteCount)
            }
            try data.write(to: fileURL, options: [.atomic])
            state = next
        } catch let error as ProviderStoreError {
            throw error
        } catch {
            throw ProviderStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    private nonisolated static func validated(_ profile: ProviderProfile) throws -> ProviderProfile {
        let identifier = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, identifier == profile.id else {
            throw ProviderStoreError.invalidIdentifier
        }
        guard identifier.utf8.count <= maximumProviderIdentifierByteCount else {
            throw ProviderStoreError.metadataLimitExceeded(
                "provider identifier exceeds \(maximumProviderIdentifierByteCount) UTF-8 bytes"
            )
        }
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw ProviderStoreError.invalidName
        }
        guard profile.name.utf8.count <= maximumProviderNameByteCount else {
            throw ProviderStoreError.metadataLimitExceeded(
                "provider name exceeds \(maximumProviderNameByteCount) UTF-8 bytes"
            )
        }
        guard profile.baseURL.absoluteString.utf8.count <= maximumBaseURLByteCount else {
            throw ProviderStoreError.metadataLimitExceeded(
                "provider base URL exceeds \(maximumBaseURLByteCount) UTF-8 bytes"
            )
        }
        guard let scheme = profile.baseURL.scheme?.lowercased(),
              let host = profile.baseURL.host?.lowercased(),
              !host.isEmpty else {
            throw ProviderStoreError.invalidBaseURL
        }
        guard profile.baseURL.user == nil, profile.baseURL.password == nil else {
            throw ProviderStoreError.baseURLCredentialsNotAllowed
        }
        guard profile.baseURL.fragment?.isEmpty != false else {
            throw ProviderStoreError.baseURLFragmentNotAllowed
        }
        guard scheme == "https" || (scheme == "http" && isLoopbackHost(host)) else {
            throw ProviderStoreError.insecureBaseURL
        }
        guard profile.protocolType.supportedWireAPIs.contains(profile.wireAPI) else {
            throw ProviderStoreError.unsupportedWireAPI(
                profile.protocolType,
                profile.wireAPI
            )
        }
        if let queryItem = URLComponents(
            url: profile.baseURL,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { isSensitiveQueryItemName($0.name) }) {
            throw ProviderStoreError.secretQueryItemNotAllowed(queryItem.name)
        }

        guard profile.defaultHeaders.count <= maximumHeadersPerProvider else {
            throw ProviderStoreError.metadataLimitExceeded(
                "provider contains more than \(maximumHeadersPerProvider) default headers"
            )
        }
        var normalizedHeaderNames = Set<String>()
        for (headerName, value) in profile.defaultHeaders.sorted(by: { $0.key < $1.key }) {
            guard isValidHTTPHeaderName(headerName) else {
                throw ProviderStoreError.invalidHeaderName(headerName)
            }
            guard headerName.utf8.count <= maximumHeaderNameByteCount else {
                throw ProviderStoreError.metadataLimitExceeded(
                    "header name exceeds \(maximumHeaderNameByteCount) UTF-8 bytes"
                )
            }
            guard value.utf8.count <= maximumHeaderValueByteCount else {
                throw ProviderStoreError.metadataLimitExceeded(
                    "header '\(headerName)' exceeds \(maximumHeaderValueByteCount) UTF-8 bytes"
                )
            }
            guard !containsProhibitedHeaderValueCharacter(value) else {
                throw ProviderStoreError.invalidHeaderValue(headerName)
            }
            let normalizedName = headerName.lowercased()
            guard normalizedHeaderNames.insert(normalizedName).inserted else {
                throw ProviderStoreError.duplicateHeaderName(headerName)
            }
            guard !isRoutingHeaderName(normalizedName) else {
                throw ProviderStoreError.routingHeaderNotAllowed(headerName)
            }
            guard !isSensitiveHeaderName(headerName) else {
                throw ProviderStoreError.secretHeaderNotAllowed(headerName)
            }
        }

        guard profile.models.count <= maximumModelsPerProvider else {
            throw ProviderStoreError.metadataLimitExceeded(
                "provider contains more than \(maximumModelsPerProvider) models"
            )
        }
        var modelIDs = Set<String>()
        for model in profile.models {
            let identifier = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, identifier == model.id else {
                throw ProviderStoreError.duplicateModelIdentifier(model.id)
            }
            guard identifier.utf8.count <= maximumModelIdentifierByteCount else {
                throw ProviderStoreError.metadataLimitExceeded(
                    "model identifier exceeds \(maximumModelIdentifierByteCount) UTF-8 bytes"
                )
            }
            guard modelIDs.insert(identifier).inserted else {
                throw ProviderStoreError.duplicateModelIdentifier(identifier)
            }
            guard model.displayName.utf8.count <= maximumModelDisplayNameByteCount else {
                throw ProviderStoreError.metadataLimitExceeded(
                    "model display name exceeds \(maximumModelDisplayNameByteCount) UTF-8 bytes"
                )
            }
            if let providerName = model.providerName,
               providerName.utf8.count > maximumModelProviderNameByteCount {
                throw ProviderStoreError.metadataLimitExceeded(
                    "model provider name exceeds \(maximumModelProviderNameByteCount) UTF-8 bytes"
                )
            }
            if let description = model.description,
               description.utf8.count > maximumModelDescriptionByteCount {
                throw ProviderStoreError.metadataLimitExceeded(
                    "model description exceeds \(maximumModelDescriptionByteCount) UTF-8 bytes"
                )
            }
            guard model.modalities.count <= maximumModelModalityCount else {
                throw ProviderStoreError.metadataLimitExceeded(
                    "model contains more than \(maximumModelModalityCount) modalities"
                )
            }
            var modalities = Set<String>()
            for modality in model.modalities {
                guard !modality.isEmpty,
                      modality.utf8.count <= maximumModelModalityByteCount,
                      modalities.insert(modality).inserted else {
                    throw ProviderStoreError.metadataLimitExceeded(
                        "model contains invalid or duplicate modality metadata"
                    )
                }
            }
            if let modelsDevProviderID = model.modelsDevProviderID,
               modelsDevProviderID.utf8.count > maximumProviderIdentifierByteCount {
                throw ProviderStoreError.metadataLimitExceeded(
                    "models.dev provider identifier exceeds its safety limit"
                )
            }
            if let contextWindow = model.contextWindow, contextWindow <= 0 {
                throw ProviderStoreError.invalidModelLimits(identifier)
            }
            if let maxOutputTokens = model.maxOutputTokens, maxOutputTokens <= 0 {
                throw ProviderStoreError.invalidModelLimits(identifier)
            }
            if let contextWindow = model.contextWindow,
               let maxOutputTokens = model.maxOutputTokens,
               maxOutputTokens > contextWindow {
                throw ProviderStoreError.invalidModelLimits(identifier)
            }
        }
        return profile
    }

    private nonisolated static func validatedProfiles(
        _ profiles: [ProviderProfile]
    ) throws -> [ProviderProfile] {
        guard profiles.count <= maximumProviderCount else {
            throw ProviderStoreError.metadataLimitExceeded(
                "store contains more than \(maximumProviderCount) providers"
            )
        }
        var identifiers = Set<String>()
        var totalModelCount = 0
        var totalHeaderCount = 0
        let validatedProfiles = try profiles.map { profile in
            let validated = try validated(profile)
            guard identifiers.insert(validated.id).inserted else {
                throw ProviderStoreError.duplicateProviderIdentifier(validated.id)
            }
            totalModelCount += validated.models.count
            totalHeaderCount += validated.defaultHeaders.count
            return validated
        }
        guard totalModelCount <= maximumTotalModelCount else {
            throw ProviderStoreError.metadataLimitExceeded(
                "store contains more than \(maximumTotalModelCount) models"
            )
        }
        guard totalHeaderCount <= maximumTotalHeaderCount else {
            throw ProviderStoreError.metadataLimitExceeded(
                "store contains more than \(maximumTotalHeaderCount) default headers"
            )
        }
        return validatedProfiles
    }

    private nonisolated static func validatedState(
        _ state: PersistedState
    ) throws -> PersistedState {
        var state = state
        state.profiles = try validatedProfiles(state.profiles)
        return state
    }

    private nonisolated static func emptyState() -> PersistedState {
        PersistedState(
            schemaVersion: PersistedState.currentSchemaVersion,
            profiles: []
        )
    }

    /// Reads at most one byte beyond the accepted limit so a file that grows
    /// after `fstat` still cannot cause an unbounded allocation. `O_NOFOLLOW`
    /// also prevents a local symlink swap from redirecting the metadata read.
    private nonisolated static func readPersistedDataIfPresent(
        from fileURL: URL
    ) throws -> Data? {
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == ENOENT {
                return nil
            }
            if errorCode == ELOOP {
                throw ProviderStoreError.storeFileNotRegular
            }
            throw ProviderStoreError.corruptedStore(
                "open failed: \(posixErrorMessage(errorCode))"
            )
        }
        defer { _ = Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw ProviderStoreError.corruptedStore(
                "fstat failed: \(posixErrorMessage(errno))"
            )
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            throw ProviderStoreError.storeFileNotRegular
        }
        guard metadata.st_size >= 0,
              metadata.st_size <= off_t(maximumStoreByteCount) else {
            throw ProviderStoreError.storeFileTooLarge(maximumStoreByteCount)
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)

        while true {
            let remainingCapacity = maximumStoreByteCount + 1 - data.count
            guard remainingCapacity > 0 else {
                throw ProviderStoreError.storeFileTooLarge(maximumStoreByteCount)
            }
            let requestedByteCount = min(buffer.count, remainingCapacity)
            let readByteCount = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.read(descriptor, baseAddress, requestedByteCount)
            }

            if readByteCount == 0 {
                break
            }
            if readByteCount < 0 {
                let errorCode = errno
                if errorCode == EINTR {
                    continue
                }
                throw ProviderStoreError.corruptedStore(
                    "read failed: \(posixErrorMessage(errorCode))"
                )
            }
            data.append(contentsOf: buffer.prefix(readByteCount))
            guard data.count <= maximumStoreByteCount else {
                throw ProviderStoreError.storeFileTooLarge(maximumStoreByteCount)
            }
        }
        return data
    }

    private nonisolated static func posixErrorMessage(_ errorCode: Int32) -> String {
        String(cString: strerror(errorCode))
    }

    private nonisolated static func isValidHTTPHeaderName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.utf8.allSatisfy { byte in
            switch byte {
            case 48...57, 65...90, 97...122,
                 33, 35...39, 42...43, 45...46, 94...96, 124, 126:
                true
            default:
                false
            }
        }
    }

    private nonisolated static func containsProhibitedHeaderValueCharacter(
        _ value: String
    ) -> Bool {
        value.utf8.contains { byte in
            (byte < 32 && byte != 9) || byte == 127
        }
    }

    private nonisolated static func isRoutingHeaderName(_ normalizedName: String) -> Bool {
        let exactNames: Set<String> = [
            "connection",
            "content-length",
            "expect",
            "forwarded",
            "host",
            "keep-alive",
            "proxy-connection",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
            "via",
            "x-http-method-override",
            "x-rewrite-url"
        ]
        return exactNames.contains(normalizedName)
            || normalizedName.hasPrefix("forwarded-")
            || normalizedName.hasPrefix("x-forwarded-")
            || normalizedName.hasPrefix("x-original-")
            || normalizedName.hasPrefix("x-envoy-original-")
    }

    private nonisolated static func isLoopbackHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" {
            return true
        }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              components.first == "127",
              components.allSatisfy({ UInt8($0) != nil }) else {
            return false
        }
        return true
    }

    private nonisolated static func isSensitiveQueryItemName(_ name: String) -> Bool {
        let normalized = normalizedSecretName(name)
        let exactNames: Set<String> = [
            "code",
            "key",
            "password",
            "passwd",
            "sig",
            "signature"
        ]
        return exactNames.contains(normalized) || isSensitiveHeaderName(normalized)
    }

    private nonisolated static func normalizedSecretName(_ name: String) -> String {
        let camelCaseSeparated = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1-$2",
                options: .regularExpression
            )
            .lowercased()

        var normalized = ""
        for character in camelCaseSeparated {
            if character.isLetter || character.isNumber {
                normalized.append(character)
            } else if !normalized.hasSuffix("-") {
                normalized.append("-")
            }
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

extension ProviderStore: ProviderStoring {}
