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
}

nonisolated protocol CloudSyncTransport: Sendable {
    func accountID() async throws -> String
    func fetch(since token: Data?) async throws -> CloudSyncPage
    func upload(_ envelope: CloudSyncEnvelope) async throws
}

/// Append-only records make a retried upload idempotent, preserve conflicting
/// versions, and avoid overwriting a peer's data with an unconditional save.
actor CloudKitSyncTransport: CloudSyncTransport {
    nonisolated static let containerIdentifier = "iCloud.omnimind.ocean.ViaVera"
    private let zoneID = CKRecordZone.ID(zoneName: "OmniBotSyncV1", ownerName: CKCurrentUserDefaultName)
    private var container: CKContainer?
    private var cachedAccountID: String?
    private var zoneReady = false
    private var resetUploadState = false

    private func connectedContainer() throws -> CKContainer {
        if let container { return container }
        // iCloud Drive's ubiquityIdentityToken is NOT a CloudKit availability
        // check. Guard the Objective-C construction exception, then use the
        // CloudKit account APIs so sync also works without iCloud Drive.
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
        if cachedAccountID != id { zoneReady = false }
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

    func fetch(since token: Data?) async throws -> CloudSyncPage {
        let database = try await database()
        let decoded = try token.flatMap {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        do {
            // Assets can be large. Decode one version per page to keep memory
            // bounded instead of retaining many attachment payloads together.
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: resetUploadState ? nil : decoded, resultsLimit: 1)
            var envelopes: [CloudSyncEnvelope] = []
            for result in page.modificationResultsByID.values {
                let record = try result.get().record
                guard record.recordType == "OmniBotSyncItem",
                      let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
                    throw CloudSyncError.invalidData
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let maximum = CloudSyncScope.maximumDocumentBytes * 2
                let data = try handle.read(upToCount: maximum + 1) ?? Data()
                guard data.count <= maximum else { throw CloudSyncError.dataTooLarge }
                let envelope = try JSONDecoder().decode(CloudSyncEnvelope.self, from: data)
                guard envelope.schemaVersion == 1,
                      (envelope.revision?.id ?? envelope.backup?.id) == record.recordID.recordName else {
                    throw CloudSyncError.invalidData
                }
                envelopes.append(envelope)
            }
            // The application never deletes versions. An external zone reset
            // does not imply that local conversations should be deleted.
            let result = CloudSyncPage(records: envelopes,
                                 token: try NSKeyedArchiver.archivedData(withRootObject: page.changeToken, requiringSecureCoding: true),
                                 moreComing: page.moreComing, resetUploadState: resetUploadState,
                                 deletedIDs: page.deletions.map { $0.recordID.recordName })
            resetUploadState = false
            return result
        } catch let error as CKError where error.code == .changeTokenExpired {
            return try await fetch(since: nil)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            zoneReady = false
            return try await fetch(since: nil)
        }
    }

    func upload(_ envelope: CloudSyncEnvelope) async throws {
        guard let id = envelope.revision?.id ?? envelope.backup?.id else { throw CloudSyncError.invalidData }
        let database = try await database()
        let directory = FileManager.default.temporaryDirectory.appending(path: "OmniBotSync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "payload.json")
        try JSONEncoder().encode(envelope).write(to: url, options: .atomic)
        let record = CKRecord(recordType: "OmniBotSyncItem", recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        record["payload"] = CKAsset(fileURL: url)
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // UUID versions are immutable. A duplicate after a lost response is
            // safe only if the server contains the identical envelope.
            guard let server = error.serverRecord,
                  let asset = server["payload"] as? CKAsset, let assetURL = asset.fileURL,
                  let existing = try? Data(contentsOf: assetURL),
                  let decoded = try? JSONDecoder().decode(CloudSyncEnvelope.self, from: existing),
                  decoded.revision == envelope.revision, decoded.backup == envelope.backup,
                  decoded.payload == envelope.payload else { throw error }
        }
    }
}
