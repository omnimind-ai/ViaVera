import SwiftUI

#if os(iOS)
struct ISHUpstreamTerminalViewRepresentable: UIViewRepresentable {
    let terminalView: UIView
    let focusRequestID: UInt

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.mount(terminalView)
        return terminalView
    }

    func updateUIView(_ terminalView: UIView, context: Context) {
        context.coordinator.requestFocus(
            for: terminalView,
            requestID: focusRequestID
        )
    }

    static func dismantleUIView(_ terminalView: UIView, coordinator: Coordinator) {
        coordinator.unmount(terminalView)
    }

    final class Coordinator {
        private weak var mountedTerminalView: UIView?
        private var pendingFocusTask: Task<Void, Never>?
        private var lastFocusRequestID: UInt = 0

        func mount(_ terminalView: UIView) {
            guard mountedTerminalView !== terminalView else { return }
            pendingFocusTask?.cancel()
            pendingFocusTask = nil
            mountedTerminalView = terminalView
            lastFocusRequestID = 0
        }

        func requestFocus(for terminalView: UIView, requestID: UInt) {
            mount(terminalView)
            guard lastFocusRequestID != requestID else { return }
            lastFocusRequestID = requestID

            pendingFocusTask?.cancel()
            pendingFocusTask = Task { @MainActor [weak self, weak terminalView] in
                // Calling becomeFirstResponder() from updateUIView re-enters
                // SwiftUI's focus graph while AttributeGraph is updating. On
                // physical iOS 26 devices that cycle can hold the main thread
                // until the scene-update watchdog terminates the app.
                await Task.yield()
                guard !Task.isCancelled,
                      let self,
                      let terminalView,
                      self.mountedTerminalView === terminalView,
                      terminalView.window != nil,
                      !terminalView.isFirstResponder else {
                    return
                }
                terminalView.becomeFirstResponder()
                self.pendingFocusTask = nil
            }
        }

        func unmount(_ terminalView: UIView) {
            guard mountedTerminalView === terminalView else { return }
            pendingFocusTask?.cancel()
            pendingFocusTask = nil
            mountedTerminalView = nil

            Task { @MainActor [weak terminalView] in
                // Keep responder changes outside SwiftUI's dismantle pass too.
                await Task.yield()
                guard let terminalView,
                      terminalView.window == nil,
                      terminalView.isFirstResponder else {
                    return
                }
                terminalView.resignFirstResponder()
            }
        }
    }
}
#endif
