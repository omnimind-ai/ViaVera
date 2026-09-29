import Foundation

// Metadata, credential comparison, and promotion run without suspension on the
// provider actor, sharing the same serialization boundary as settings edits.
extension ProviderStore {
    func syncDocuments(keychain: any APIKeyStoring) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for profile in profiles() {
            result["provider/\(profile.id)"] = try CloudSyncCoding.encode(snapshot(profile, keychain: keychain))
        }
        return result
    }

    private func snapshot(_ profile: ProviderProfile, keychain: any APIKeyStoring) throws -> CloudSyncProviderDocument {
        let binding = ProviderEndpointIdentity.canonical(for: profile)
        let key = try keychain.apiKey(for: profile.id)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential: CloudSyncProviderDocument.Credential?
        if let key, !key.isEmpty, try keychain.endpointBinding(for: profile.id) == binding {
            guard key.utf8.count <= 64 * 1_024 else { throw CloudSyncError.dataTooLarge }
            credential = .init(apiKey: key, endpointBinding: binding)
        } else {
            credential = nil
        }
        return CloudSyncProviderDocument(profile: profile, credential: credential)
    }

    func applySyncDocument(key: String, data: Data?, expectedDigest: String?, keychain: any APIKeyStoring) throws -> Bool {
        let id = String(key.dropFirst("provider/".count))
        let current = profile(id: id)
        let previous = try current.map { try snapshot($0, keychain: keychain) }
        let currentData = try previous.map(CloudSyncCoding.encode)
        let legacyData = try current.map(CloudSyncCoding.encode)
        guard currentData.map(CloudSyncRevision.hash) == expectedDigest
                || (previous?.credential == nil && legacyData.map(CloudSyncRevision.hash) == expectedDigest) else { return false }

        let incoming: CloudSyncProviderDocument?
        if let data {
            if let document = try? JSONDecoder().decode(CloudSyncProviderDocument.self, from: data) {
                guard document.schemaVersion == 1 else { throw CloudSyncError.invalidData }
                incoming = document
            } else {
                // Backups from before credential sync contain only a profile.
                // Preserve a current key only when the protected endpoint matches.
                let profile = try JSONDecoder().decode(ProviderProfile.self, from: data)
                let binding = ProviderEndpointIdentity.canonical(for: profile)
                incoming = CloudSyncProviderDocument(profile: profile,
                    credential: previous?.credential?.endpointBinding == binding ? previous?.credential : nil)
            }
            guard let incoming, incoming.profile.id == id else { throw CloudSyncError.invalidData }
            try ProviderStore.validate(incoming.profile)
            if let credential = incoming.credential {
                guard !credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      credential.apiKey.utf8.count <= 64 * 1_024,
                      credential.endpointBinding == ProviderEndpointIdentity.canonical(for: incoming.profile) else {
                    throw CloudSyncError.invalidData
                }
            }
        } else {
            incoming = nil
        }

        // Remove the binding first. Even if a Keychain write fails halfway,
        // runtime credential checks cannot use a key at an unintended endpoint.
        do {
            try replaceCredential(nil, id: id, keychain: keychain)
            if let incoming { try upsert(incoming.profile) }
            else if current != nil { try remove(id: id) }
            try replaceCredential(incoming?.credential, id: id, keychain: keychain)
        } catch {
            try? replaceCredential(nil, id: id, keychain: keychain)
            // Best-effort rollback, with endpoint binding still enforced if a
            // second disk/Keychain error prevents full rollback.
            if let previous {
                if (try? upsert(previous.profile)) != nil {
                    try? replaceCredential(previous.credential, id: id, keychain: keychain)
                }
            } else {
                try? remove(id: id)
            }
            throw CloudSyncError.credentialStorage
        }
        return true
    }

    private func replaceCredential(_ credential: CloudSyncProviderDocument.Credential?, id: String, keychain: any APIKeyStoring) throws {
        try keychain.deleteEndpointBinding(for: id)
        try keychain.deleteAPIKey(for: id)
        if let credential {
            try keychain.saveAPIKey(credential.apiKey, for: id)
            try keychain.saveEndpointBinding(credential.endpointBinding, for: id)
        }
    }
}
