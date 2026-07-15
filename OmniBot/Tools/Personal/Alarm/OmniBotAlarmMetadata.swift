#if os(iOS)
import AlarmKit
import Foundation

nonisolated struct OmniBotAlarmMetadata: AlarmMetadata {
    let title: String
    let message: String?
    let triggerAt: Date
    let timeZoneIdentifier: String?
}
#endif
