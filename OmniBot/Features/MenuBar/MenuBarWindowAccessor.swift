#if os(macOS)
import SwiftUI

struct MenuBarWindowAccessor: NSViewRepresentable {
    let reference: MenuBarWindowReference

    func makeNSView(context: Context) -> MenuBarWindowAccessView {
        MenuBarWindowAccessView(reference: reference)
    }

    func updateNSView(_ view: MenuBarWindowAccessView, context: Context) {
        reference.window = view.window
    }
}
#endif
