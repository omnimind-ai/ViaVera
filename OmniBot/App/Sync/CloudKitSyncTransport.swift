import CloudKit
import Foundation
#if SWIFT_PACKAGE
import OmniCloudKitBridge
#endif

nonisolated struct CloudSyncEnvelope: Codable, Sendable {
    var schemaVersion = 1
    var revision: CloudSyncRevision?
    var backup: CloudSyncBackup?
    var payload: Data?
}

nonisolated struct CloudSyncPage: Sendable {
    var records: [CloudSyncEnvelope]
    var token: Data
    var moreComing: Bool
    var resetUploadState = false
    var deletedIDs: [String] = []
    var beginsFullFetch = false
}

nonisolated protocol CloudSyncTransport: Sendable {
    func accountID() async throws -> String
    func beginSession() async throws
    func endSession() async
    func fetch(since token: Data?) async throws -> CloudSyncPage
    func upload(_ envelope: CloudSyncEnvelope) async throws
    func deleteRecords(_ ids: [String]) async throws
}

/// A fenced lease serializes fetch/write/retention across devices. Every write
/// atomically updates the lease's change tag, so an expired session cannot
/// delete records after another device has acquired the zone.
actor CloudKitSyncTransport: CloudSyncTransport {
    nonisolated static let containerIdentifier = "iCloud.omnimind.ocean.ViaVera"
    private let zoneID = CKRecordZone.ID(zoneName: "OmniBotSyncV1", ownerName: CKCurrentUserDefaultName)
    private let leaseName = "OmniBotSyncLeaseV2"
    private let sessionID = UUID().uuidString
    private var container: CKContainer?
    private var cachedAccountID: String?
    private var zoneReady = false
    private var resetUploadState = false
    private var sessionRecord: CKRecord?

    private struct Lease: Codable {
        // Older apps stop at this marker rather than re-uploading pruned data.
        var schemaVersion = 2
        let owner: String?
        let expiresAt: Date
    }

    private func connectedContainer() throws -> CKContainer {
        if let container { return container }
        guard let container = OmniCloudKitContainerWithIdentifier(Self.containerIdentifier) else {
            throw CloudSyncError.unavailable
        }
        self.container = container
        return container
    }

    func accountID() async throws -> String {
        let container = try connectedContainer()
        guard try await container.accountStatus() == .available else { throw CloudSyncError.unavailable }
        let id = try await container.userRecordID().recordName
        if cachedAccountID != id { zoneReady = false; sessionRecord = nil }
        cachedAccountID = id
        return id
    }

    private func database() async throws -> CKDatabase {
        let database = try connectedContainer().privateCloudDatabase
        if zoneReady { return database }
        do {
            _ = try await database.recordZone(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            resetUploadState = true
        }
        zoneReady = true
        return database
    }

    func beginSession() async throws {
        let database = try await database()
        let id = CKRecord.ID(recordName: leaseName, zoneID: zoneID)
        var record: CKRecord
        do {
            record = try await database.record(for: id)
            let lease = try JSONDecoder().decode(Lease.self, from: assetData(record))
            guard lease.schemaVersion == 2 else { throw CloudSyncError.invalidData }
            guard lease.owner == nil || lease.owner == sessionID || lease.expiresAt <= .now else {
                throw CloudSyncError.cloudBusy
            }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: "OmniBotSyncItem", recordID: id)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            zoneReady = false
            return try await beginSession()
        }
        sessionRecord = record
        try await mutate()
    }

    func endSession() async {
        guard sessionRecord != nil else { return }
        try? await mutate(releasing: true)
        sessionRecord = nil
    }

    /// CloudKit assets are encrypted by CloudKit. Temporary plaintext needed
    /// for CKAsset uploads is private to the user and removed after completion.
    private func temporaryAsset(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "OmniBotSync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appending(path: "payload.json")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func assetData(_ record: CKRecord) throws -> Data {
        guard record.recordType == "OmniBotSyncItem",
              let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
            throw CloudSyncError.invalidData
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let maximum = CloudSyncScope.maximumDocumentBytes * 2
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw CloudSyncError.dataTooLarge }
        return data
    }

    private func envelope(_ record: CKRecord) throws -> CloudSyncEnvelope {
        let envelope = try JSONDecoder().decode(CloudSyncEnvelope.self, from: assetData(record))
        guard envelope.schemaVersion == 1,
              (envelope.revision?.id ?? envelope.backup?.id) == record.recordID.recordName else {
            throw CloudSyncError.invalidData
        }
        return envelope
    }

    private func mutate(saving: [CKRecord] = [], deleting: [CKRecord.ID] = [], releasing: Bool = false) async throws {
        guard let lease = sessionRecord else { throw CloudSyncError.cloudBusy }
        let database = try await database()
        let url = try temporaryAsset(JSONEncoder().encode(Lease(owner: releasing ? nil : sessionID,
                                                               expiresAt: Date.now.addingTimeInterval(releasing ? 0 : 180))))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        lease["payload"] = CKAsset(fileURL: url)
        do {
            let result = try await database.modifyRecords(saving: [lease] + saving, deleting: deleting,
                                                          savePolicy: .ifServerRecordUnchanged, atomically: true)
            for value in result.saveResults.values { _ = try value.get() }
            for value in result.deleteResults.values { _ = try value.get() }
            guard let saved = try result.saveResults[lease.recordID]?.get() else { throw CloudSyncError.invalidData }
            sessionRecord = saved
        } catch {
            // A failed/ambiguous commit must reacquire and refetch before any
            // subsequent mutation. Never silently retry a stale retention plan.
            sessionRecord = nil
            if let error = error as? CKError, error.code == .serverRecordChanged || error.code == .batchRequestFailed {
                throw CloudSyncError.cloudBusy
            }
            throw error
        }
    }

    func fetch(since token: Data?) async throws -> CloudSyncPage {
        // Renew with CAS before reading: theft of an expired lease fences off
        // this session. Upload/delete operations also include this same fence.
        if let modified = sessionRecord?.modificationDate, Date.now.timeIntervalSince(modified) < 60 {
            // Writes still validate the tag; read-only fetches may use this lease.
        } else {
            try await mutate()
        }
        let database = try await database()
        let decoded = try token.flatMap {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        do {
            let fullFetch = resetUploadState || token == nil
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: resetUploadState ? nil : decoded, resultsLimit: 1)
            var envelopes: [CloudSyncEnvelope] = []
            for result in page.modificationResultsByID.values {
                let record = try result.get().record
                if record.recordID.recordName == leaseName { continue }
                envelopes.append(try envelope(record))
            }
            let result = CloudSyncPage(records: envelopes,
                token: try NSKeyedArchiver.archivedData(withRootObject: page.changeToken, requiringSecureCoding: true),
                moreComing: page.moreComing, resetUploadState: resetUploadState,
                deletedIDs: page.deletions.map { $0.recordID.recordName }.filter { $0 != leaseName },
                beginsFullFetch: fullFetch)
            resetUploadState = false
            return result
        } catch let error as CKError where error.code == .changeTokenExpired {
            return try await fetch(since: nil)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            zoneReady = false
            sessionRecord = nil
            throw CloudSyncError.cloudBusy
        }
    }

    func upload(_ envelope: CloudSyncEnvelope) async throws {
        guard let id = envelope.revision?.id ?? envelope.backup?.id else { throw CloudSyncError.invalidData }
        let database = try await database()
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        do {
            let existing = try self.envelope(await database.record(for: recordID))
            guard existing.revision == envelope.revision, existing.backup == envelope.backup,
                  existing.payload == envelope.payload else { throw CloudSyncError.invalidData }
            return
        } catch let error as CKError where error.code == .unknownItem { }
        let url = try temporaryAsset(JSONEncoder().encode(envelope))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let record = CKRecord(recordType: "OmniBotSyncItem", recordID: recordID)
        record["payload"] = CKAsset(fileURL: url)
        try await mutate(saving: [record])
    }

    func deleteRecords(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        guard ids.count <= 100, ids.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw CloudSyncError.invalidData }
        let database = try await database()
        // Ignore already-deleted records after an interrupted cleanup.
        let records = try await database.records(for: ids.map { CKRecord.ID(recordName: $0, zoneID: zoneID) })
        var existing: [CKRecord.ID] = []
        for (id, result) in records {
            do { _ = try result.get(); existing.append(id) }
            catch let error as CKError where error.code == .unknownItem { }
        }
        try await mutate(deleting: existing)
    }
}
