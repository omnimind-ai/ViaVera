#if os(macOS)
import AppKit
import Testing
@testable import Via_Vera

@Suite("Menu bar window appearance")
@MainActor
struct MenuBarWindowAccessViewTests {
    @Test("Applies the selected theme on attachment and updates the open panel")
    func updatesAttachedPanelAppearance() throws {
        let reference = MenuBarWindowReference()
        let view = MenuBarWindowAccessView(reference: reference, themeMode: .dark)
        let panel = makePanel()
        let contentView = try #require(panel.contentView)
        contentView.addSubview(view)

        #expect(reference.window === panel)
        #expect(panel.appearance?.name == .darkAqua)
        #expect(contentView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)

        view.updateThemeMode(.light)
        #expect(panel.appearance?.name == .aqua)
        #expect(contentView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)

        view.updateThemeMode(.system)
        #expect(panel.appearance == nil)
        #expect(panel.effectiveAppearance.name == NSApplication.shared.effectiveAppearance.name)
    }

    @Test("Uses the latest theme when the menu bar panel is recreated")
    func appliesThemeAfterReattachment() throws {
        let reference = MenuBarWindowReference()
        let view = MenuBarWindowAccessView(reference: reference, themeMode: .light)
        let firstPanel = makePanel()
        let firstContentView = try #require(firstPanel.contentView)
        firstContentView.addSubview(view)
        #expect(firstPanel.appearance?.name == .aqua)

        view.removeFromSuperview()
        #expect(reference.window == nil)
        view.updateThemeMode(.dark)

        let reopenedPanel = makePanel()
        let reopenedContentView = try #require(reopenedPanel.contentView)
        reopenedContentView.addSubview(view)

        #expect(reference.window === reopenedPanel)
        #expect(reopenedPanel.appearance?.name == .darkAqua)
        #expect(firstPanel.appearance?.name == .aqua)
    }

    private func makePanel() -> NSPanel {
        NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }
}
#endif
