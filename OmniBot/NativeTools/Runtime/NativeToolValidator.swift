import Foundation

nonisolated enum NativeToolValidator {
    static let maximumPackageBytes = 256 * 1_024
    static let maximumStateBytes = 1_024 * 1_024

    static func decode(_ data: Data) throws -> NativeToolPackage {
        guard data.count <= maximumPackageBytes else { throw NativeToolError("工具包不能超过 256 KB。") }
        // Check raw JSON nesting before recursively decoding Swift values.
        let raw = try JSONSerialization.jsonObject(with: data)
        try checkRaw(raw, depth: 0)
        try validateShape(raw)
        let package: NativeToolPackage
        do { package = try JSONDecoder().decode(NativeToolPackage.self, from: data) }
        catch { throw NativeToolError("工具包字段不完整或类型错误：\(error.localizedDescription)") }
        func containsLegacy(_ nodes: [NativeToolComponent]) -> Bool {
            nodes.contains { $0.type == .totp || containsLegacy($0.children ?? []) }
        }
        guard !package.screens.contains(where: { containsLegacy($0.components) }) else {
            throw NativeToolError("totp 整体组件已停用。请使用通用组件与 invoke 能力调用组合工具。")
        }
        try validate(package)
        return package
    }

    static func validate(_ package: NativeToolPackage) throws {
        guard try JSONEncoder().encode(package).count <= maximumPackageBytes else { throw NativeToolError("工具包不能超过 256 KB。") }
        guard package.schemaVersion == 1, package.stateVersion == 1 else {
            throw NativeToolError("当前仅支持 schemaVersion=1、stateVersion=1；更新不能改变数据版本。")
        }
        guard !package.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              package.name.count <= 80, (package.summary?.count ?? 0) <= 500,
              (package.symbol?.count ?? 0) <= 100 else { throw NativeToolError("工具名称或说明长度不合法。") }
        guard !package.screens.isEmpty, package.screens.count <= 12,
              package.initialState.count <= 100, package.actions.count <= 100,
              Set(package.capabilities).isSubset(of: NativeToolCapabilityRegistry.permissions.union(["totp"])),
              Set(package.capabilities).count == package.capabilities.count else {
            throw NativeToolError("页面、状态、动作数量或能力声明不受支持。")
        }
        guard package.initialState.keys.allSatisfy(validKey) else { throw NativeToolError("状态键必须是字母开头的简单标识符。") }
        try validateState(package.initialState)
        let session = package.sessionState ?? [:]
        guard session.count <= 100, session.keys.allSatisfy(validKey),
              Set(session.keys).isDisjoint(with: package.initialState.keys) else { throw NativeToolError("会话状态键无效或与持久状态重复。") }
        try validateState(session)
        let allKeys = Set(package.initialState.keys).union(session.keys)
        let screens = Set(package.screens.map(\.id))
        guard screens.count == package.screens.count, screens.allSatisfy(validKey) else {
            throw NativeToolError("页面 ID 无效或重复。")
        }
        var ids = Set<String>()
        var count = 0
        for screen in package.screens {
            guard !screen.title.isEmpty, screen.title.count <= 100, !screen.components.isEmpty else { throw NativeToolError("页面需要标题和至少一个组件。") }
            for node in screen.components {
                try validate(node, package: package, ids: &ids, count: &count, depth: 0, insideList: false)
            }
        }
        for (id, steps) in package.actions {
            guard validKey(id), !steps.isEmpty, steps.count <= 32 else { throw NativeToolError("动作 ID 或步骤数量无效。") }
            for step in steps {
                if let condition = step.when { try validateExpression(condition, keys: allKeys) }
                if step.type == .invoke {
                    guard let operation = step.operation else { throw NativeToolError("invoke 需要 operation。") }
                    let entry = try NativeToolCapabilityRegistry.resolve(operation, declared: package.capabilities)
                    try NativeToolCapabilityRegistry.validate(step.arguments ?? [:], for: entry, evaluated: false)
                    for expression in (step.arguments ?? [:]).values { try validateExpression(expression, keys: allKeys) }
                    if let key = step.result, session[key]?.objectValue == nil { throw NativeToolError("能力结果只能写入已声明的对象类型会话状态。") }
                } else if step.type == .setSession {
                    guard let key = step.key, session[key] != nil, let value = step.value else { throw NativeToolError("setSession 需要会话状态键和 value。") }
                    try validateExpression(value, keys: allKeys)
                } else if step.type == .navigate {
                    guard let screen = step.screen, screens.contains(screen) else { throw NativeToolError("动作引用了不存在的页面。") }
                } else {
                    if let value = step.value {
                        try validateExpression(value, keys: Set(package.initialState.keys))
                        if !session.isEmpty, [.set, .append].contains(step.type), containsItem(value) {
                            throw NativeToolError("能力列表数据只能写入会话状态，不能复制到持久状态。")
                        }
                    }
                    guard let key = step.key, package.initialState[key] != nil else { throw NativeToolError("动作引用了不存在的状态。") }
                    if step.type != .set, package.initialState[key]?.arrayValue == nil {
                        throw NativeToolError("集合动作需要数组状态。")
                    }
                    if step.type == .set || step.type == .append {
                        guard step.value != nil else { throw NativeToolError("set 和 append 必须提供 value。") }
                    }
                    if step.type == .toggleItem, !(step.field.map(validKey) ?? false) {
                        throw NativeToolError("toggleItem 必须提供字段名。")
                    }
                }
            }
        }
        if let refresh = package.onRefresh {
            guard let steps = package.actions[refresh], steps.allSatisfy({ step in
                guard step.type == .invoke, let operation = step.operation else { return false }
                return (try? NativeToolCapabilityRegistry.resolve(operation, declared: package.capabilities).passive) == true
            }) else { throw NativeToolError("onRefresh 只能调用已声明的被动读取能力。") }
        }
    }

    static func validateState(_ state: [String: AgentValue]) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= maximumStateBytes else { throw NativeToolError("工具数据超过 1 MB 上限。") }
        try checkRaw(JSONSerialization.jsonObject(with: data), depth: 0)
        for value in state.values {
            if let array = value.arrayValue {
                guard array.count <= 500 else { throw NativeToolError("每个集合最多保存 500 条记录。") }
                let ids = array.compactMap { $0.objectValue?["id"]?.stringValue }
                guard ids.count == array.count, Set(ids).count == ids.count,
                      ids.allSatisfy({ !$0.isEmpty && $0.count <= 100 }) else {
                    throw NativeToolError("集合中的每条记录必须具有唯一的字符串 id。")
                }
            }
        }
    }

    static func validKey(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil
    }

    private static func validate(
        _ node: NativeToolComponent, package: NativeToolPackage,
        ids: inout Set<String>, count: inout Int, depth: Int, insideList: Bool
    ) throws {
        count += 1
        guard depth <= 8, count <= 200, validKey(node.id), ids.insert(node.id).inserted else {
            throw NativeToolError("组件 ID 重复、无效或数量/嵌套层级超过上限。")
        }
        guard (node.title?.count ?? 0) <= 500 else { throw NativeToolError("组件标题过长。") }
        if let action = node.action, package.actions[action] == nil { throw NativeToolError("组件引用了不存在的动作：\(action)") }
        if let binding = node.binding, package.initialState[binding] == nil { throw NativeToolError("组件引用了不存在的状态：\(binding)") }
        if let binding = node.sessionBinding, package.sessionState?[binding] == nil { throw NativeToolError("组件引用了不存在的会话状态。") }
        guard node.binding == nil || node.sessionBinding == nil else { throw NativeToolError("组件不能同时绑定两类状态。") }
        let keys = Set(package.initialState.keys).union((package.sessionState ?? [:]).keys)
        if let value = node.value { try validateExpression(value, keys: keys) }
        if let value = node.visibleWhen { try validateExpression(value, keys: keys) }
        switch node.type {
        case .textField, .secureField, .numberField, .toggle, .picker:
            guard let value = node.binding.flatMap({ package.initialState[$0] }) ?? node.sessionBinding.flatMap({ package.sessionState?[$0] }) else { throw NativeToolError("输入组件必须绑定状态。") }
            switch (node.type, value) {
            case (.textField, .string), (.secureField, .string), (.picker, .string), (.numberField, .number), (.toggle, .bool): break
            default: throw NativeToolError("输入组件与绑定状态的类型不匹配。")
            }
            if node.type == .secureField, node.sessionBinding == nil { throw NativeToolError("密码输入必须绑定会话状态。") }
            if node.type == .picker {
                guard let options = node.options, !options.isEmpty, options.count <= 50,
                      Set(options).count == options.count, options.allSatisfy({ $0.count <= 200 }),
                      options.contains(value.stringValue ?? "") else { throw NativeToolError("选择器选项或初始值无效。") }
            }
        case .button:
            guard node.action != nil, node.title?.isEmpty == false else { throw NativeToolError("按钮需要标题和动作。") }
        case .list:
            guard !insideList, node.binding.flatMap({ package.initialState[$0]?.arrayValue }) != nil || node.value != nil else {
                throw NativeToolError("列表必须绑定数组，且不能嵌套列表。")
            }
        case .totp:
            guard package.capabilities.contains("totp"), !insideList else { throw NativeToolError("TOTP 组件需要声明 totp 能力，并放在列表之外。") }
        default: break
        }
        let containers: Set<NativeToolComponent.Kind> = [.stack, .row, .section, .list]
        if node.children?.isEmpty == false, !containers.contains(node.type) { throw NativeToolError("该组件不支持子组件。") }
        for child in node.children ?? [] {
            try validate(child, package: package, ids: &ids, count: &count, depth: depth + 1, insideList: insideList || node.type == .list)
        }
    }

    private static func validateExpression(_ value: AgentValue, keys: Set<String>, depth: Int = 0) throws {
        guard depth <= 16 else { throw NativeToolError("表达式嵌套超过上限。") }
        if let object = value.objectValue {
            if let get = object["get"] {
                guard object.count == 1, let key = get.stringValue, keys.contains(key) else { throw NativeToolError("get 必须引用已声明的状态。") }
            } else if let item = object["item"] {
                guard object.count == 1, let field = item.stringValue, field.isEmpty || validKey(field) else { throw NativeToolError("item 字段无效。") }
            } else if let now = object["now"] {
                guard object.count == 1, now == .bool(true) else { throw NativeToolError("now 表达式无效。") }
            } else if let op = object["op"] {
                guard object.count == 2, let name = op.stringValue, NativeToolExpression.operations.contains(name),
                      let args = object["args"]?.arrayValue, args.count <= 16 else { throw NativeToolError("运算名称或参数无效。") }
                let unary: Set<String> = ["round", "trim", "uppercase", "lowercase", "count", "not"]
                let variadic: Set<String> = ["concat", "and", "or"]
                let expected = ["if", "filter"].contains(name) ? 3 : unary.contains(name) ? 1 : 2
                guard variadic.contains(name) || args.count == expected || (name == "sum" && args.count == 1) else {
                    throw NativeToolError("运算 \(name) 参数数量不正确。")
                }
            }
            for child in object.values { try validateExpression(child, keys: keys, depth: depth + 1) }
        } else if let array = value.arrayValue {
            for child in array { try validateExpression(child, keys: keys, depth: depth + 1) }
        }
    }

    private static func checkRaw(_ value: Any, depth: Int) throws {
        guard depth <= 40 else { throw NativeToolError("JSON 嵌套超过上限。") }
        if let object = value as? [String: Any] {
            guard object.count <= 200 else { throw NativeToolError("JSON 字段数量超过上限。") }
            for child in object.values { try checkRaw(child, depth: depth + 1) }
        } else if let array = value as? [Any] {
            guard array.count <= 500 else { throw NativeToolError("JSON 数组超过 500 项。") }
            for child in array { try checkRaw(child, depth: depth + 1) }
        } else if let text = value as? String, text.utf8.count > 32_768 {
            throw NativeToolError("单个文本字段超过 32 KB。")
        }
    }

    private static func validateShape(_ raw: Any) throws {
        func object(_ value: Any, allowed: Set<String>) throws -> [String: Any] {
            guard let value = value as? [String: Any], Set(value.keys).isSubset(of: allowed) else {
                throw NativeToolError("工具包包含未支持的字段；请使用内置 Skill 中的组件与动作协议。")
            }
            return value
        }
        func component(_ raw: Any) throws {
            let node = try object(raw, allowed: ["id", "type", "title", "value", "binding", "sessionBinding", "action", "children", "options", "visibleWhen"])
            for child in node["children"] as? [Any] ?? [] { try component(child) }
        }
        let root = try object(raw, allowed: ["schemaVersion", "name", "summary", "symbol", "stateVersion", "initialState", "sessionState", "onRefresh", "screens", "actions", "capabilities"])
        for rawScreen in root["screens"] as? [Any] ?? [] {
            let screen = try object(rawScreen, allowed: ["id", "title", "components"])
            for node in screen["components"] as? [Any] ?? [] { try component(node) }
        }
        for steps in (root["actions"] as? [String: Any] ?? [:]).values {
            for step in steps as? [Any] ?? [] {
                _ = try object(step, allowed: ["type", "key", "value", "field", "screen", "when", "operation", "arguments", "result"])
            }
        }
    }

    private static func containsItem(_ value: AgentValue) -> Bool {
        if let object = value.objectValue { return object["item"] != nil || object.values.contains(where: containsItem) }
        return value.arrayValue?.contains(where: containsItem) ?? false
    }
}
