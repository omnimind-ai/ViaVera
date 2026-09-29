import Foundation

nonisolated enum CloudSyncRetention {
    static let maximumBackups = 50
    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    static func expiredBackups(in state: CloudSyncIndex, now: Date = .now) -> [String] {
        let ordered = state.backups.values.sorted {
            $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date
        }
        return ordered.enumerated().compactMap { offset, backup in
            guard offset > 0, state.uploaded.contains(backup.id) else { return nil }
            return offset >= maximumBackups || now.timeIntervalSince(backup.date) > maximumAge ? backup.id : nil
        }
    }

    static func unusedRevisions(in state: CloudSyncIndex) -> [String] {
        var protected = Set(state.localHeads.values)
        protected.formUnion(state.winningHeads.values.map(\.id))
        for backup in state.backups.values { protected.formUnion(backup.heads.values) }
        return state.revisions.keys.filter { !protected.contains($0) && state.uploaded.contains($0) }.sorted()
    }
}
