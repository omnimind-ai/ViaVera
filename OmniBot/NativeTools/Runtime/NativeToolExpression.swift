import Foundation

/// Bounded JSON expression trees. No eval, reflection, host objects, or I/O.
nonisolated enum NativeToolExpression {
    static let operations: Set<String> = [
        "add", "subtract", "multiply", "divide", "round", "min", "max",
        "concat", "trim", "uppercase", "lowercase", "count", "sum",
        "equal", "greater", "less", "not", "and", "or", "if", "contains",
    ]

    static func evaluate(
        _ expression: AgentValue,
        state: [String: AgentValue],
        item: AgentValue = .null,
        now: Date = .now,
        depth: Int = 0
    ) throws -> AgentValue {
        let result = try evaluateValue(expression, state: state, item: item, now: now, depth: depth)
        var remainingBytes = NativeToolValidator.maximumStateBytes
        try measure(result, remainingBytes: &remainingBytes, depth: 0)
        return result
    }

    private static func evaluateValue(
        _ expression: AgentValue,
        state: [String: AgentValue],
        item: AgentValue = .null,
        now: Date = .now,
        depth: Int = 0
    ) throws -> AgentValue {
        guard depth <= 16 else { throw NativeToolError("表达式嵌套超过上限。") }
        func eval(_ value: AgentValue) throws -> AgentValue {
            try evaluate(value, state: state, item: item, now: now, depth: depth + 1)
        }
        switch expression {
        case let .array(values): return .array(try values.map(eval))
        case let .object(object):
            if let key = object["get"]?.stringValue { return state[key] ?? .null }
            if let key = object["item"]?.stringValue {
                return key.isEmpty ? item : item.objectValue?[key] ?? .null
            }
            if object["now"] == .bool(true) { return .number(now.timeIntervalSince1970) }
            guard let operation = object["op"]?.stringValue else {
                return .object(try object.mapValues(eval))
            }
            guard operations.contains(operation), let arguments = object["args"]?.arrayValue else {
                throw NativeToolError("无法识别的表达式。")
            }
            // Conditional branches are evaluated lazily (e.g. division guarded by a condition).
            if operation == "if" {
                guard arguments.count == 3 else { throw NativeToolError("if 需要三个参数。") }
                return try eval(arguments[truthy(try eval(arguments[0])) ? 1 : 2])
            }
            let values = try arguments.map(eval)
            func number(_ index: Int) throws -> Double {
                guard values.indices.contains(index) else { throw NativeToolError("表达式参数不足。") }
                let result = values[index].numberValue ?? Double(display(values[index]))
                guard let result, result.isFinite else { throw NativeToolError("请输入有效数字。") }
                return result
            }
            func finite(_ number: Double) throws -> AgentValue {
                guard number.isFinite, abs(number) <= 1e100 else { throw NativeToolError("计算结果超出范围。") }
                return .number(number)
            }
            switch operation {
            case "add": return try finite(number(0) + number(1))
            case "subtract": return try finite(number(0) - number(1))
            case "multiply": return try finite(number(0) * number(1))
            case "divide":
                let divisor = try number(1)
                guard divisor != 0 else { throw NativeToolError("除数不能为零。") }
                return try finite(number(0) / divisor)
            case "round": return try finite(number(0).rounded())
            case "min": return try finite(min(number(0), number(1)))
            case "max": return try finite(max(number(0), number(1)))
            case "concat":
                var text = ""
                for value in values {
                    let part = display(value)
                    guard text.utf8.count + part.utf8.count <= 32_768 else { throw NativeToolError("计算生成的文本超过 32 KB。") }
                    text += part
                }
                return .string(text)
            case "trim": return .string(display(values.first ?? .null).trimmingCharacters(in: .whitespacesAndNewlines))
            case "uppercase": return .string(display(values.first ?? .null).uppercased())
            case "lowercase": return .string(display(values.first ?? .null).lowercased())
            case "count":
                let value = values.first ?? .null
                return .number(Double(value.arrayValue?.count ?? display(value).count))
            case "sum":
                let entries = values.first?.arrayValue ?? []
                let field = values.count > 1 ? values[1].stringValue : nil
                return try finite(entries.reduce(0) { sum, entry in
                    let value = field.flatMap { entry.objectValue?[$0] } ?? entry
                    guard let amount = value.numberValue else { throw NativeToolError("汇总字段必须是数字。") }
                    return sum + amount
                })
            case "equal": return .bool(values.count == 2 && values[0] == values[1])
            case "greater": return .bool(try number(0) > number(1))
            case "less": return .bool(try number(0) < number(1))
            case "not": return .bool(!truthy(values.first ?? .null))
            case "and": return .bool(values.allSatisfy(truthy))
            case "or": return .bool(values.contains(where: truthy))
            case "contains":
                guard values.count == 2 else { throw NativeToolError("contains 需要两个参数。") }
                return .bool(display(values[0]).localizedStandardContains(display(values[1])))
            default: throw NativeToolError("不支持的运算。")
            }
        default: return expression
        }
    }

    static func truthy(_ value: AgentValue) -> Bool {
        switch value {
        case .null: false
        case let .bool(value): value
        case let .number(value): value != 0
        case let .string(value): !value.isEmpty
        case let .array(value): !value.isEmpty
        case let .object(value): !value.isEmpty
        }
    }

    static func display(_ value: AgentValue) -> String {
        switch value {
        case .null: ""
        case let .string(value): value
        case let .number(value): value.formatted(.number.precision(.fractionLength(0...8)))
        case let .bool(value): value ? "是" : "否"
        case .array, .object:
            (try? String(decoding: JSONEncoder().encode(value), as: UTF8.self)) ?? ""
        }
    }

    /// Account for intermediate results before encoding or persisting them.
    /// Collection references can otherwise amplify a tiny expression into huge JSON.
    private static func measure(_ value: AgentValue, remainingBytes: inout Int, depth: Int) throws {
        guard depth <= 40, remainingBytes >= 0 else { throw NativeToolError("计算结果超过数据上限。") }
        remainingBytes -= 16
        switch value {
        case let .string(text):
            guard text.utf8.count <= 32_768 else { throw NativeToolError("计算生成的文本超过 32 KB。") }
            remainingBytes -= text.utf8.count
        case let .array(values):
            guard values.count <= 500 else { throw NativeToolError("计算生成的集合超过 500 项。") }
            for child in values { try measure(child, remainingBytes: &remainingBytes, depth: depth + 1) }
        case let .object(values):
            guard values.count <= 200 else { throw NativeToolError("计算生成的字段超过上限。") }
            for (key, child) in values {
                remainingBytes -= key.utf8.count
                try measure(child, remainingBytes: &remainingBytes, depth: depth + 1)
            }
        default: break
        }
        guard remainingBytes >= 0 else { throw NativeToolError("计算结果超过数据上限。") }
    }
}
