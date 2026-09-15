import Foundation
import Observation

@MainActor
@Observable
final class NativeToolRuntime {
    let record: NativeToolRecord
    let isPreview: Bool
    private(set) var state: [String: AgentValue]
    private(set) var sessionState: [String: AgentValue]
    private(set) var isPerforming = false
    var screenID: String
    var errorMessage: String?
    private(set) var persistenceFailed = false
    var isSaving: Bool { pendingSaves > 0 }
    private var pendingSaves = 0
    private let store: NativeToolStore
    private var stateRevision: Int
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    private let host: (any NativeToolHostCalling)?
    private var generation = UUID()
    private var hostSessionID: UUID?

    init(document: NativeToolDocument, store: NativeToolStore, isPreview: Bool = false, host: (any NativeToolHostCalling)? = nil) {
        record = document.record
        state = document.state
        sessionState = document.record.package.sessionState ?? [:]
        self.host = host
        hostSessionID = host?.sessionID
        stateRevision = document.stateRevision
        screenID = document.record.package.screens[0].id
        self.store = store
        self.isPreview = isPreview
    }

    var screen: NativeToolScreen {
        record.package.screens.first(where: { $0.id == screenID }) ?? record.package.screens[0]
    }

    func value(_ expression: AgentValue?, item: AgentValue = .null, now: Date = .now) -> AgentValue {
        guard let expression else { return .null }
        // Render-time evaluation has no state mutations or side effects.
        return (try? NativeToolExpression.evaluate(expression, state: state.merging(sessionState) { _, session in session }, item: item, now: now)) ?? .null
    }

    func set(_ value: AgentValue, for key: String) {
        guard !persistenceFailed, state[key] != value else { return }
        var updated = state
        updated[key] = value
        do {
            try NativeToolActionEngine.validateTypes(updated, package: record.package)
            try NativeToolValidator.validateState(updated)
            state = updated
            persist()
        } catch { errorMessage = error.localizedDescription }
    }

    func perform(_ action: String, item: AgentValue = .null) {
        guard !persistenceFailed, !isPerforming else { return }
        if record.package.sessionState != nil || record.package.actions[action]?.contains(where: { $0.type == .invoke }) == true {
            isPerforming = true
            let token = generation
            actionTask = Task { await execute(action, item: item, token: token) }
            return
        }
        do {
            let result = try NativeToolActionEngine.perform(action, package: record.package, state: state, item: item)
            if result.state != state {
                state = result.state
                persist()
            }
            if let screen = result.screenID { screenID = screen }
        } catch { errorMessage = error.localizedDescription }
    }

    func flush() async { await saveTask?.value }

    func finishActions() async { await actionTask?.value }

    func setSession(_ value: AgentValue, for key: String) {
        guard let initial = record.package.sessionState?[key], NativeToolActionEngine.sameType(initial, value) else { return }
        var updated = sessionState
        updated[key] = value
        do { try NativeToolValidator.validateState(updated); sessionState = updated }
        catch { errorMessage = error.localizedDescription }
    }

    func refresh() async {
        guard !isPreview, !isPerforming, let action = record.package.onRefresh else { return }
        isPerforming = true
        await execute(action, item: .null, token: generation)
    }

    func suspend() {
        generation = UUID()
        actionTask?.cancel()
        actionTask = nil
        host?.suspend()
        sessionState = record.package.sessionState ?? [:]
        isPerforming = false
    }

    private func execute(_ action: String, item: AgentValue, token: UUID) async {
        defer { if generation == token { isPerforming = false } }
        do {
            guard let steps = record.package.actions[action] else { throw NativeToolError("找不到此动作。") }
            for step in steps {
                try Task.checkCancellation()
                guard generation == token else { return }
                if let condition = step.when, !NativeToolExpression.truthy(value(condition, item: item)) { continue }
                switch step.type {
                case .invoke:
                    guard !isPreview, let host, let operation = step.operation else { throw NativeToolError("安装工具后才能调用设备能力。") }
                    let entry = try NativeToolCapabilityRegistry.resolve(operation, declared: record.package.capabilities)
                    let arguments = try (step.arguments ?? [:]).mapValues {
                        try NativeToolExpression.evaluate($0, state: state.merging(sessionState) { _, session in session }, item: item)
                    }
                    try NativeToolCapabilityRegistry.validate(arguments, for: entry, evaluated: true)
                    let result = try await host.invoke(operation, arguments: arguments)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    syncHostSession()
                    if let key = step.result {
                        var updated = sessionState
                        updated[key] = result
                        try NativeToolValidator.validateState(updated)
                        sessionState = updated
                    }
                case .setSession:
                    if let key = step.key, let expression = step.value {
                        let result = try NativeToolExpression.evaluate(expression, state: state.merging(sessionState) { _, session in session }, item: item)
                        guard let initial = record.package.sessionState?[key], NativeToolActionEngine.sameType(initial, result) else { throw NativeToolError("会话状态类型不能改变。") }
                        sessionState[key] = result
                    }
                case .navigate:
                    if let screen = step.screen { screenID = screen }
                default:
                    var step = step
                    step.when = nil
                    var package = record.package
                    package = NativeToolPackage(schemaVersion: package.schemaVersion, name: package.name, summary: package.summary, symbol: package.symbol,
                        stateVersion: package.stateVersion, initialState: package.initialState, screens: package.screens,
                        actions: ["step": [step]], capabilities: package.capabilities)
                    let result = try NativeToolActionEngine.perform("step", package: package, state: state, item: item)
                    if result.state != state { state = result.state; persist() }
                }
            }
        } catch is CancellationError { }
        catch { if generation == token { syncHostSession(); errorMessage = error.localizedDescription } }
    }

    private func syncHostSession() {
        if hostSessionID != host?.sessionID {
            hostSessionID = host?.sessionID
            sessionState = record.package.sessionState ?? [:]
        }
    }

    private func persist() {
        guard !isPreview else { return }
        let snapshot = state
        let previous = saveTask
        pendingSaves += 1
        saveTask = Task {
            defer { pendingSaves -= 1 }
            await previous?.value
            guard !persistenceFailed else { return }
            do {
                stateRevision = try await store.saveState(
                    snapshot, for: record.id, packageRevision: record.revision,
                    expectedStateRevision: stateRevision
                )
            } catch {
                persistenceFailed = true
                errorMessage = "数据尚未保存：\(error.localizedDescription)"
            }
        }
    }
}
