#if os(macOS)
import AppKit
import Testing
@testable import Via_Vera

@Suite("Settings titlebar dismissal")
@MainActor
struct SettingsTitlebarDismissViewTests {
    @Test("A titlebar click closes settings and is consumed before reaching toolbar actions")
    func consumesTitlebarClick() throws {
        let window = makeWindow()
        var dismissCount = 0
        let view = SettingsTitlebarDismissView { dismissCount += 1 }
        let contentView = try #require(window.contentView)
        contentView.addSubview(view)
        defer { view.removeFromSuperview() }

        let event = try mouseDown(in: window, at: titlebarPoint(in: window))
        #expect(view.handleMouseDown(event) == nil)
        #expect(dismissCount == 1)

        view.stopMonitoring()
        #expect(view.handleMouseDown(event) === event)
        #expect(dismissCount == 1)
    }

    @Test("Settings content and other windows retain their own mouse handling")
    func preservesContentAndOtherWindows() throws {
        let window = makeWindow()
        let otherWindow = makeWindow()
        var dismissCount = 0
        let view = SettingsTitlebarDismissView { dismissCount += 1 }
        let contentView = try #require(window.contentView)
        contentView.addSubview(view)
        defer { view.removeFromSuperview() }

        let contentEvent = try mouseDown(
            in: window,
            at: NSPoint(x: window.contentLayoutRect.midX, y: window.contentLayoutRect.midY)
        )
        let otherWindowEvent = try mouseDown(in: otherWindow, at: titlebarPoint(in: otherWindow))

        #expect(view.handleMouseDown(contentEvent) === contentEvent)
        #expect(view.handleMouseDown(otherWindowEvent) === otherWindowEvent)
        #expect(dismissCount == 0)
    }

    @Test("Standard window controls remain available and detaching restores titlebar handling")
    func preservesWindowControlsAndDetaches() throws {
        let window = makeWindow()
        var dismissCount = 0
        let view = SettingsTitlebarDismissView { dismissCount += 1 }
        let contentView = try #require(window.contentView)
        contentView.addSubview(view)
        defer { view.removeFromSuperview() }

        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try #require(window.standardWindowButton(buttonType))
            let frame = button.convert(button.bounds, to: nil)
            let event = try mouseDown(in: window, at: NSPoint(x: frame.midX, y: frame.midY))
            #expect(view.handleMouseDown(event) === event)
        }

        let titlebarEvent = try mouseDown(in: window, at: titlebarPoint(in: window))
        view.removeFromSuperview()
        #expect(view.handleMouseDown(titlebarEvent) === titlebarEvent)
        #expect(dismissCount == 0)

        contentView.addSubview(view)
        #expect(view.handleMouseDown(titlebarEvent) == nil)
        #expect(dismissCount == 1)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.toolbar = NSToolbar(identifier: "SettingsTitlebarTests-\(UUID().uuidString)")
        return window
    }

    private func titlebarPoint(in window: NSWindow) -> NSPoint {
        NSPoint(
            x: window.frame.width / 2,
            y: (window.contentLayoutRect.maxY + window.frame.height) / 2
        )
    }

    private func mouseDown(in window: NSWindow, at point: NSPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
#endif
