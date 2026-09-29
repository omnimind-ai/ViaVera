#if os(macOS)
import AppKit

final class ShortcutEventMonitorView: NSView {
    var handleKey: (NSEvent) -> Bool = { _ in false }
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let window = self.window,
                      window.isKeyWindow, event.window === window,
                      window.attachedSheet == nil else { return false }
                return self.handleKey(event)
            }
            return handled ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
#endif
