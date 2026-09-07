#if os(macOS)
import AppKit

final class MenuBarWindowAccessView: NSView {
    private let reference: MenuBarWindowReference
    private var themeMode: AppearanceThemeMode

    init(reference: MenuBarWindowReference, themeMode: AppearanceThemeMode) {
        self.reference = reference
        self.themeMode = themeMode
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reference.window = window
        applyThemeMode()
    }

    func updateThemeMode(_ themeMode: AppearanceThemeMode) {
        self.themeMode = themeMode
        applyThemeMode()
    }

    private func applyThemeMode() {
        guard let window else { return }
        // MenuBarExtra's native panel needs the appearance as well as SwiftUI's preference.
        let appearance: NSAppearance? = switch themeMode {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
        if window.appearance?.name != appearance?.name {
            window.appearance = appearance
        }
    }
}
#endif
