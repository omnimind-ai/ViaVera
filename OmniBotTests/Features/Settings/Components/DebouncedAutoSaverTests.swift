import Foundation
import Testing
@testable import Via_Vera

@Suite("Debounced settings auto-save")
@MainActor
struct DebouncedAutoSaverTests {
    @Test("Rapid edits save only the latest snapshot")
    func rapidEditsAreCoalesced() async throws {
        var savedValues: [Int] = []
        let saver = DebouncedAutoSaver<Int>(delay: .milliseconds(20))
        saver.configure(lastSavedValue: 0) { value in
            savedValues.append(value)
            return value
        }

        saver.submit(1)
        saver.submit(2)
        saver.submit(3)

        try await Task.sleep(for: .milliseconds(100))

        #expect(savedValues == [3])
    }

    @Test("Edits made during a save retain only the latest pending snapshot")
    func inFlightEditsStayBounded() async throws {
        var savedValues: [Int] = []
        var concurrentSaveCount = 0
        var maximumConcurrentSaveCount = 0
        let saver = DebouncedAutoSaver<Int>(delay: .milliseconds(10))
        saver.configure(lastSavedValue: 0) { value in
            concurrentSaveCount += 1
            maximumConcurrentSaveCount = max(
                maximumConcurrentSaveCount,
                concurrentSaveCount
            )
            savedValues.append(value)
            try? await Task.sleep(for: .milliseconds(50))
            concurrentSaveCount -= 1
            return value
        }

        saver.submit(1)
        try await Task.sleep(for: .milliseconds(25))
        saver.submit(2)
        saver.submit(3)
        try await Task.sleep(for: .milliseconds(150))

        #expect(savedValues == [1, 3])
        #expect(maximumConcurrentSaveCount == 1)
    }
}
