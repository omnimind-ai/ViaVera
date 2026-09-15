import Foundation
import Observation

@MainActor
@Observable
final class NativeToolRuntime {
    let record: NativeToolRecord
    let isPreview: Bool
    private(set) var state: [String: AgentValue]
    var screenID: String
    var errorMessage: String?
    private(set) var persistenceFailed = false
    var isSaving: Bool { pendingSaves > 0 }
    private var pendingSaves = 0
    private let store: NativeToolStore
    private var stateRevision: Int
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(document: NativeToolDocument, store: NativeToolStore, isPreview: Bool = false) {
        record = document.record
        state = document.state
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
        return (try? NativeToolExpression.evaluate(expression, state: state, item: item, now: now)) ?? .null
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
        guard !persistenceFailed else { return }
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
