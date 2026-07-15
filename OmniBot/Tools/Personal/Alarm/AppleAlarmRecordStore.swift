import Foundation

actor AppleAlarmRecordStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let maximumRecordCount = 256
    private let maximumFileBytes = 512 * 1_024

    init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = .default
    }

    func upsert(_ record: OmniBotAlarmRecord) throws {
        var records = try load()
        records.removeAll { $0.alarmID == record.alarmID }
        guard records.count < maximumRecordCount else {
            throw ApplePersonalToolError(
                "OmniBot's private alarm record limit of \(maximumRecordCount) has been reached.",
                code: "maximum_limit_reached",
                backend: record.backend
            )
        }
        records.append(record)
        try save(records)
    }

    func all() throws -> [OmniBotAlarmRecord] {
        try load()
    }

    @discardableResult
    func remove(alarmID: String) throws -> Bool {
        var records = try load()
        let originalCount = records.count
        records.removeAll { $0.alarmID == alarmID }
        guard records.count != originalCount else { return false }
        try save(records)
        return true
    }

    func reconcile(activeAlarmIDs: Set<String>) throws -> [OmniBotAlarmRecord] {
        let records = try load()
        let activeRecords = records.filter { activeAlarmIDs.contains($0.alarmID) }
        if activeRecords.count != records.count {
            try save(activeRecords)
        }
        return activeRecords
    }

    private func load() throws -> [OmniBotAlarmRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard byteCount <= maximumFileBytes else {
            throw ApplePersonalToolError(
                "The private alarm record file exceeds its \(maximumFileBytes)-byte safety limit.",
                code: "record_store_too_large",
                backend: "host_control"
            )
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([OmniBotAlarmRecord].self, from: data)
            guard records.count <= maximumRecordCount else {
                throw ApplePersonalToolError(
                    "The private alarm record file exceeds its \(maximumRecordCount)-record safety limit.",
                    code: "record_store_too_large",
                    backend: "host_control"
                )
            }
            return records
        } catch let error as ApplePersonalToolError {
            throw error
        } catch {
            throw ApplePersonalToolError(
                "The private alarm record file is not valid JSON: \(error.localizedDescription)",
                code: "record_store_corrupt",
                backend: "host_control"
            )
        }
    }

    private func save(_ records: [OmniBotAlarmRecord]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records.sorted { $0.createdAt < $1.createdAt })
        guard data.count <= maximumFileBytes else {
            throw ApplePersonalToolError(
                "The private alarm record file would exceed its \(maximumFileBytes)-byte safety limit.",
                code: "record_store_too_large",
                backend: "host_control"
            )
        }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
