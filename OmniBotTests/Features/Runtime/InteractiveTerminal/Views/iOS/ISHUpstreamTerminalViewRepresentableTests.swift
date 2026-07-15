#if os(iOS)
import Testing
import UIKit
@testable import Via_Vera

@MainActor
@Suite("iSH terminal focus scheduling")
struct ISHUpstreamTerminalViewRepresentableTests {
    @Test("Focus changes are deferred beyond the SwiftUI update pass")
    func defersFocusChange() async {
        let fixture = makeFixture()

        fixture.coordinator.requestFocus(for: fixture.terminalView, requestID: 1)

        #expect(fixture.terminalView.focusRequestCount == 0)
        await waitForScheduledTasks()
        #expect(fixture.terminalView.focusRequestCount == 1)
    }

    @Test("Unmounting cancels a pending focus change")
    func unmountCancelsPendingFocus() async {
        let fixture = makeFixture()

        fixture.coordinator.requestFocus(for: fixture.terminalView, requestID: 1)
        fixture.coordinator.unmount(fixture.terminalView)

        await waitForScheduledTasks()
        #expect(fixture.terminalView.focusRequestCount == 0)
    }

    @Test("Repeated updates for one request do not refocus the terminal")
    func ignoresRepeatedRequestIdentifier() async {
        let fixture = makeFixture()

        fixture.coordinator.requestFocus(for: fixture.terminalView, requestID: 1)
        fixture.coordinator.requestFocus(for: fixture.terminalView, requestID: 1)

        await waitForScheduledTasks()
        #expect(fixture.terminalView.focusRequestCount == 1)
    }

    private func makeFixture() -> FocusFixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let terminalView = FocusRecordingView(frame: window.bounds)
        window.addSubview(terminalView)
        let coordinator = ISHUpstreamTerminalViewRepresentable.Coordinator()
        coordinator.mount(terminalView)
        return FocusFixture(
            window: window,
            terminalView: terminalView,
            coordinator: coordinator
        )
    }

    private func waitForScheduledTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

@MainActor
private struct FocusFixture {
    let window: UIWindow
    let terminalView: FocusRecordingView
    let coordinator: ISHUpstreamTerminalViewRepresentable.Coordinator
}

@MainActor
private final class FocusRecordingView: UIView {
    private(set) var focusRequestCount = 0

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        focusRequestCount += 1
        return true
    }
}
#endif
