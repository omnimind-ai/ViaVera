#if os(macOS)
import SwiftUI

struct MenuBarWindowAccessor: NSViewRepresentable {
    let reference: MenuBarWindowReference
    let themeMode: AppearanceThemeMode

    func makeNSView(context: Context) -> MenuBarWindowAccessView {
        MenuBarWindowAccessView(reference: reference, themeMode: themeMode)
    }

    func updateNSView(_ view: MenuBarWindowAccessView, context: Context) {
        reference.window = view.window
        view.updateThemeMode(themeMode)
    }
}
#endif
