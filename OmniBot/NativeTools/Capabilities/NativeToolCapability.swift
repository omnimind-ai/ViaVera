import Foundation

nonisolated struct NativeToolCapability: Sendable {
    let operation: String
    let parameters: [String: String]
    let required: Set<String>
    let result: String
    var passive = false

    var permission: String { String(operation.prefix(while: { $0 != "." })) }

    var value: AgentValue {
        .object([
            "operation": .string(operation), "capability": .string(permission),
            "parameters": .object(parameters.mapValues(AgentValue.string)),
            "required": .array(required.sorted().map(AgentValue.string)),
            "result": .string(result), "passive": .bool(passive),
        ])
    }
}
