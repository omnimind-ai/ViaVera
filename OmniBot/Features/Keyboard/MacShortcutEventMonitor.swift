#if os(macOS)
import AppKit
import SwiftUI

struct MacShortcutEventMonitor: NSViewRepresentable {
    let handleKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ShortcutEventMonitorView {
        let view = ShortcutEventMonitorView()
        view.handleKey = handleKey
        return view
    }

    func updateNSView(_ view: ShortcutEventMonitorView, context: Context) {
        view.handleKey = handleKey
    }

    static func dismantleNSView(_ view: ShortcutEventMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}
#endif
