import Foundation

nonisolated enum NativeToolActionEngine {
    struct Result: Sendable {
        let state: [String: AgentValue]
        let screenID: String?
    }

    static func perform(
        _ actionID: String, package: NativeToolPackage,
        state: [String: AgentValue], item: AgentValue = .null, now: Date = .now
    ) throws -> Result {
        guard let steps = package.actions[actionID] else { throw NativeToolError("找不到此动作。") }
        var updated = state
        var screenID: String?
        for step in steps {
            if let condition = step.when,
               !NativeToolExpression.truthy(try NativeToolExpression.evaluate(condition, state: updated, item: item, now: now)) {
                continue
            }
            if step.type == .navigate {
                screenID = step.screen
                continue
            }
            guard let key = step.key else { throw NativeToolError("动作缺少状态键。") }
            let value = try step.value.map { try NativeToolExpression.evaluate($0, state: updated, item: item, now: now) }
            switch step.type {
            case .set:
                updated[key] = value ?? .null
            case .append:
                guard var entries = updated[key]?.arrayValue, var entry = value?.objectValue else {
                    throw NativeToolError("新增记录必须是对象。")
                }
                entry["id"] = .string(UUID().uuidString)
                entries.append(.object(entry))
                updated[key] = .array(entries)
            case .remove, .toggleItem:
                guard var entries = updated[key]?.arrayValue,
                      let identifier = value?.stringValue ?? item.objectValue?["id"]?.stringValue,
                      let index = entries.firstIndex(where: { $0.objectValue?["id"]?.stringValue == identifier }) else {
                    throw NativeToolError("该记录已不存在，请重新打开工具。")
                }
                if step.type == .remove {
                    entries.remove(at: index)
                } else {
                    guard var entry = entries[index].objectValue, let field = step.field,
                          case let .bool(flag) = entry[field] else { throw NativeToolError("切换字段必须是布尔值。") }
                    entry[field] = .bool(!flag)
                    entries[index] = .object(entry)
                }
                updated[key] = .array(entries)
            case .navigate: break
            case .invoke, .setSession: throw NativeToolError("此动作需要能力运行时。")
            }
        }
        try validateTypes(updated, package: package)
        try NativeToolValidator.validateState(updated)
        return Result(state: updated, screenID: screenID)
    }

    static func validateTypes(_ state: [String: AgentValue], package: NativeToolPackage) throws {
        for (key, initial) in package.initialState {
            guard let current = state[key], sameType(initial, current) else {
                throw NativeToolError("状态 \(key) 的数据类型不能改变。")
            }
        }
    }

    static func sameType(_ lhs: AgentValue, _ rhs: AgentValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null), (.string, .string), (.number, .number), (.bool, .bool), (.array, .array), (.object, .object): true
        default: false
        }
    }
}
