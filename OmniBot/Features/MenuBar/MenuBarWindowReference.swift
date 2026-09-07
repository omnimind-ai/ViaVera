#if os(macOS)
import AppKit

@MainActor
final class MenuBarWindowReference {
    weak var window: NSWindow?

    func hide() {
        window?.orderOut(nil)
    }
}
#endif
