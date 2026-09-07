#if os(macOS)
import AppKit

final class SettingsTitlebarDismissView: NSView {
    var onDismiss: () -> Void
    private var eventMonitor: Any?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let wasHandled = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleMouseDown(event) == nil
            }
            return wasHandled ? nil : event
        }
    }

    func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard eventMonitor != nil,
              let window,
              event.window === window,
              window.attachedSheet == nil,
              event.locationInWindow.y >= window.contentLayoutRect.maxY else {
            return event
        }

        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(buttonType),
               !button.isHiddenOrHasHiddenAncestor,
               button.convert(button.bounds, to: nil).contains(event.locationInWindow) {
                return event
            }
        }

        // Native titlebar controls sit outside the SwiftUI overlay's hit-testing area.
        onDismiss()
        return nil
    }
}
#endif
