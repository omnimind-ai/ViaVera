import Foundation

nonisolated struct OmniBotAlarmRecord: Codable, Hashable, Sendable {
    let alarmID: String
    let backend: String
    let title: String
    let message: String?
    let triggerAt: Date
    let timeZoneIdentifier: String?
    let exact: Bool
    let createdAt: Date

    var agentValue: AgentValue {
        .object([
            "alarmId": .string(alarmID),
            "backend": .string(backend),
            "title": .string(title),
            "message": message.map(AgentValue.string) ?? .null,
            "triggerAt": .string(ApplePersonalToolParsing.iso8601(triggerAt)),
            "timezone": timeZoneIdentifier.map(AgentValue.string) ?? .null,
            "exact": .bool(exact),
            "createdAt": .string(ApplePersonalToolParsing.iso8601(createdAt)),
        ])
    }
}
