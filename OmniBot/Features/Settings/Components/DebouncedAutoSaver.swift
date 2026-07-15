import Foundation

@MainActor
final class DebouncedAutoSaver<Value: Equatable> {
    typealias SaveAction = @MainActor (Value) async -> Value?

    private let delay: Duration
    private var activeTask: Task<Void, Never>?
    private var pendingValue: Value?
    private var lastSavedValue: Value?
    private var saveAction: SaveAction?
    private var isSaving = false
    private var flushRequested = false

    init(delay: Duration) {
        self.delay = delay
    }

    func configure(lastSavedValue: Value, save: @escaping SaveAction) {
        activeTask?.cancel()
        activeTask = nil
        pendingValue = nil
        self.lastSavedValue = lastSavedValue
        saveAction = save
        flushRequested = false
    }

    func submit(_ value: Value) {
        guard saveAction != nil else { return }

        // An in-flight save may change what is persisted. Keep even a value
        // equal to the previous snapshot so a user reversal is not lost.
        if isSaving {
            pendingValue = value
            return
        }

        guard value != lastSavedValue else {
            pendingValue = nil
            activeTask?.cancel()
            activeTask = nil
            return
        }

        pendingValue = value
        scheduleAfterDelay()
    }

    func flush(_ value: Value) {
        guard saveAction != nil else { return }

        flushRequested = true
        pendingValue = value

        guard !isSaving else { return }

        activeTask?.cancel()
        activeTask = nil

        guard value != lastSavedValue else {
            pendingValue = nil
            flushRequested = false
            return
        }

        startSavingImmediately()
    }

    private func scheduleAfterDelay() {
        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self?.savePendingValue()
        }
    }

    private func startSavingImmediately() {
        // A flush is commonly triggered by view disappearance, so retain the
        // coordinator until this final bounded save finishes.
        activeTask = Task { @MainActor in
            await savePendingValue()
        }
    }

    private func savePendingValue() async {
        guard !isSaving,
              let saveAction,
              let value = pendingValue else {
            return
        }

        pendingValue = nil
        isSaving = true

        if let persistedValue = await saveAction(value) {
            lastSavedValue = persistedValue
        }

        isSaving = false

        if pendingValue == lastSavedValue {
            pendingValue = nil
        }

        guard pendingValue != nil else {
            activeTask = nil
            flushRequested = false
            return
        }

        if flushRequested {
            startSavingImmediately()
        } else {
            scheduleAfterDelay()
        }
    }
}
