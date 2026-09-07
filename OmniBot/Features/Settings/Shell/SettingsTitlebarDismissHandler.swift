#if os(macOS)
import SwiftUI

struct SettingsTitlebarDismissHandler: NSViewRepresentable {
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> SettingsTitlebarDismissView {
        SettingsTitlebarDismissView(onDismiss: onDismiss)
    }

    func updateNSView(_ view: SettingsTitlebarDismissView, context: Context) {
        view.onDismiss = onDismiss
    }

    static func dismantleNSView(_ view: SettingsTitlebarDismissView, coordinator: ()) {
        view.stopMonitoring()
    }
}
#endif
