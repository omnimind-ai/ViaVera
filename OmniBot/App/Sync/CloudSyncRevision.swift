import CryptoKit
import Foundation

/// Immutable cloud versions: deletes are tombstones, never an absent file.
/// Lamport clocks and stable device IDs converge without relying on wall clocks.
nonisolated struct CloudSyncRevision: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let key: String
    let deviceID: String
    let counter: Int64
    let date: Date
    let digest: String?

    func precedes(_ other: Self) -> Bool {
        if counter != other.counter { return counter < other.counter }
        if deviceID != other.deviceID { return deviceID < other.deviceID }
        return id < other.id
    }

    static func hash(_ data: Data) -> String {
        let digits = Array("0123456789abcdef")
        return String(SHA256.hash(data: data).flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] })
    }
}

nonisolated struct CloudSyncBackup: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let date: Date
    let deviceName: String
    let heads: [String: String]
}

nonisolated struct CloudSyncIndex: Codable, Sendable {
    var schemaVersion = 1
    var deviceID = UUID().uuidString
    var accountID: String?
    var counter: Int64 = 0
    var revisions: [String: CloudSyncRevision] = [:]
    var backups: [String: CloudSyncBackup] = [:]
    /// Versions actually installed locally, not merely downloaded.
    var localHeads: [String: String] = [:]
    var uploaded: Set<String> = []
    var changeToken: Data?
    /// Only kept until local compare-and-set applies a surviving winner.
    var retiredLocalRevisions: Set<String>?
    var fullFetchKnownIDs: Set<String>?
    var fullFetchSeenIDs: Set<String>?

    mutating func removeRemoteRecords(_ ids: some Sequence<String>) {
        let local = Set(localHeads.values)
        for id in ids {
            backups.removeValue(forKey: id)
            if local.contains(id), revisions[id] != nil {
                retiredLocalRevisions = (retiredLocalRevisions ?? []).union([id])
            } else {
                revisions.removeValue(forKey: id)
                uploaded.remove(id)
            }
        }
    }

    mutating func discardRetiredLocalRevisions() {
        let local = Set(localHeads.values)
        for id in retiredLocalRevisions ?? [] where !local.contains(id) {
            revisions.removeValue(forKey: id)
            uploaded.remove(id)
            retiredLocalRevisions?.remove(id)
        }
    }

    var winningHeads: [String: CloudSyncRevision] {
        var result: [String: CloudSyncRevision] = [:]
        for revision in revisions.values {
            if let existing = result[revision.key], !existing.precedes(revision) { continue }
            result[revision.key] = revision
        }
        return result
    }

    mutating func recordLocal(key: String, data: Data?, date: Date = .now, force: Bool = false) throws -> CloudSyncRevision? {
        try recordLocal(key: key, digest: data.map(CloudSyncRevision.hash), date: date, force: force)
    }

    mutating func recordLocal(key: String, digest: String?, date: Date = .now, force: Bool = false) throws -> CloudSyncRevision? {
        if !force, let id = localHeads[key], let previous = revisions[id], previous.digest == digest { return nil }
        if !force && localHeads[key] == nil && digest == nil { return nil }
        guard counter < Int64.max else { throw CloudSyncError.invalidData }
        counter += 1
        let revision = CloudSyncRevision(id: UUID().uuidString, key: key, deviceID: deviceID,
                                         counter: counter, date: date, digest: digest)
        revisions[revision.id] = revision
        localHeads[key] = revision.id
        return revision
    }

    mutating func receive(_ revision: CloudSyncRevision) throws {
        guard UUID(uuidString: revision.id) != nil, UUID(uuidString: revision.deviceID) != nil,
              revision.counter >= 0, CloudSyncScope.accepts(revision.key),
              revision.digest.map({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) ?? true else {
            throw CloudSyncError.invalidData
        }
        if let existing = revisions[revision.id], existing != revision { throw CloudSyncError.invalidData }
        revisions[revision.id] = revision
        counter = max(counter, revision.counter)
        uploaded.insert(revision.id)
    }
}

nonisolated enum CloudSyncError: LocalizedError {
    case unavailable, accountChanged, invalidData, dataTooLarge, busy, cloudBusy, credentialStorage

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "iCloud 不可用。请检查 Apple 账户、iCloud 设置和应用的 iCloud 签名权限。")
        case .accountChanged: String(localized: "iCloud 账户已更换。同步已暂停；请关闭再开启同步，确认将本机数据同步到当前账户。")
        case .invalidData: String(localized: "云端数据无法验证，已保留本机数据。")
        case .dataTooLarge: String(localized: "同步文件超过 64 MB，请缩小文件后重试。本机数据仍然保留。")
        case .busy: String(localized: "任务或设置编辑正在进行，结束后会自动同步。")
        case .cloudBusy: String(localized: "另一台设备正在同步，稍后会自动重试。")
        case .credentialStorage: String(localized: "API Key 安全存储读写失败，已暂停同步，请解锁设备后重试。")
        }
    }
}
