#if os(macOS)
import AppKit

final class MenuBarWindowAccessView: NSView {
    private let reference: MenuBarWindowReference

    init(reference: MenuBarWindowReference) {
        self.reference = reference
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reference.window = window
    }
}
#endif
