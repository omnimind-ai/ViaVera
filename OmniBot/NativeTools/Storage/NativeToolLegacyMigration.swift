import Foundation

nonisolated enum NativeToolLegacyMigration {
    /// Expand the old opaque component into an ordinary package, preserving tool/vault identity.
    static func upgrade(_ package: NativeToolPackage, template: NativeToolPackage) -> NativeToolPackage? {
        func containsLegacy(_ nodes: [NativeToolComponent]) -> Bool {
            nodes.contains { $0.type == .totp || containsLegacy($0.children ?? []) }
        }
        guard package.screens.contains(where: { containsLegacy($0.components) }) else { return nil }
        if package.screens.count == 1, package.screens[0].components.count == 1,
           package.screens[0].components[0].type == .totp, package.actions.isEmpty, package.initialState.isEmpty {
            return NativeToolPackage(schemaVersion: 1, name: package.name, summary: package.summary, symbol: package.symbol,
                stateVersion: 1, initialState: [:], screens: template.screens, actions: template.actions,
                capabilities: template.capabilities, sessionState: template.sessionState, onRefresh: template.onRefresh)
        }
        var actions = package.actions
        var session = package.sessionState ?? [:]
        var addedScreens: [NativeToolScreen] = []
        var refreshSteps = package.onRefresh.flatMap { actions[$0] } ?? []
        var counter = 0
        var prefix = "legacyOTP_"
        let occupied = Set(actions.keys).union(session.keys).union(package.initialState.keys).union(package.screens.map(\.id))
        while occupied.contains(where: { $0.hasPrefix(prefix) }) { prefix += "x" }

        func replace(_ nodes: [NativeToolComponent]) -> [NativeToolComponent] {
            nodes.map { node in
                var node = node
                if node.type != .totp { node.children = node.children.map(replace); return node }
                counter += 1
                let namespace = prefix + String(counter) + "_"
                func expression(_ value: AgentValue) -> AgentValue {
                    if var object = value.objectValue {
                        if let key = object["get"]?.stringValue { object["get"] = .string(namespace + key); return .object(object) }
                        return .object(object.mapValues(expression))
                    }
                    if let values = value.arrayValue { return .array(values.map(expression)) }
                    return value
                }
                func component(_ original: NativeToolComponent) -> NativeToolComponent {
                    var copy = NativeToolComponent(id: namespace + original.id, type: original.type)
                    copy.title = original.title
                    copy.value = original.value.map(expression)
                    copy.visibleWhen = original.visibleWhen.map(expression)
                    copy.action = original.action.map { namespace + $0 }
                    copy.sessionBinding = original.sessionBinding.map { namespace + $0 }
                    copy.options = original.options
                    copy.children = original.children?.map(component)
                    return copy
                }
                for (key, value) in template.sessionState ?? [:] { session[namespace + key] = value }
                for (id, steps) in template.actions {
                    actions[namespace + id] = steps.map { step in
                        var step = step
                        step.key = step.key.map { namespace + $0 }
                        step.result = step.result.map { namespace + $0 }
                        step.screen = step.screen.map { namespace + $0 }
                        step.value = step.value.map(expression)
                        step.when = step.when.map(expression)
                        step.arguments = step.arguments?.mapValues(expression)
                        return step
                    }
                }
                if let refresh = template.onRefresh { refreshSteps += actions[namespace + refresh] ?? [] }
                addedScreens += template.screens.map { NativeToolScreen(id: namespace + $0.id, title: $0.title, components: $0.components.map(component)) }
                let action = namespace + "open"
                actions[action] = [NativeToolAction(type: .navigate, screen: namespace + template.screens[0].id)]
                return NativeToolComponent(id: node.id, type: .button, title: node.title ?? "打开验证码", action: action, visibleWhen: node.visibleWhen)
            }
        }
        let screens = package.screens.map { NativeToolScreen(id: $0.id, title: $0.title, components: replace($0.components)) }
        actions[prefix + "refresh"] = refreshSteps
        return NativeToolPackage(schemaVersion: 1, name: package.name, summary: package.summary, symbol: package.symbol,
            stateVersion: 1, initialState: package.initialState, screens: screens + addedScreens, actions: actions,
            capabilities: Array(Set(package.capabilities.filter { $0 != "totp" }).union(template.capabilities)).sorted(),
            sessionState: session, onRefresh: prefix + "refresh")
    }
}
