#if os(macOS)
import Combine
import SwiftUI
import Testing
@testable import Via_Vera

@MainActor
struct MacChatComposerTextViewTests {
    @Test
    func returnAndShiftReturnHaveDistinctActions() throws {
        let textView = MacChatComposerTextView.ComposerNativeTextView()
        textView.string = "firstsecond"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        var submitCount = 0
        textView.onSubmit = { submitCount += 1 }

        let shiftReturn = try #require(makeReturnEvent(modifiers: [.shift]))
        textView.keyDown(with: shiftReturn)
        #expect(textView.string == "first\nsecond")
        #expect(submitCount == 0)

        let returnKey = try #require(makeReturnEvent())
        textView.keyDown(with: returnKey)
        #expect(textView.string == "first\nsecond")
        #expect(submitCount == 1)
    }

    @Test
    func typingKeepsTheNativeTextViewFocused() throws {
        let composerState = ComposerState()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: FocusHarness(composerState: composerState)
        )
        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.layoutSubtreeIfNeeded()

        let textView = try #require(findTextView(in: hostingView))
        #expect(window.makeFirstResponder(textView))

        for character in ["a", "b", "c"] {
            let event = try #require(makeKeyEvent(character: character))
            textView.keyDown(with: event)
            RunLoop.main.run(until: .now.addingTimeInterval(0.01))
            #expect(window.firstResponder === textView)
        }

        #expect(textView.string == "abc")
    }

    @Test
    func markedTextIsVisibleBeforeTheIMECommitsIt() throws {
        let composerState = ComposerState()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: FocusHarness(composerState: composerState)
        )
        window.contentView = hostingView
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.layoutSubtreeIfNeeded()

        let textView = try #require(
            findTextView(in: hostingView) as? MacChatComposerTextView.ComposerNativeTextView
        )
        #expect(window.makeFirstResponder(textView))

        textView.setMarkedText(
            "hahaha",
            selectedRange: NSRange(location: 6, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(textView.hasMarkedText())
        #expect(textView.hasVisibleContent)
        #expect(composerState.hasVisibleContent)
        #expect(composerState.text.isEmpty)
    }

    private func makeReturnEvent(
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
    }

    private func makeKeyEvent(character: String) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        )
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    private struct FocusHarness: View {
        @ObservedObject var composerState: ComposerState
        @State private var measuredHeight = AppDesign.composerTextLineHeight
        @State private var isFocused = false

        var body: some View {
            MacChatComposerTextView(
                text: $composerState.text,
                measuredHeight: $measuredHeight,
                isFocused: $isFocused,
                hasVisibleContent: $composerState.hasVisibleContent,
                isEnabled: true,
                maximumLines: 10,
                onSubmit: {}
            )
            .frame(width: 480, height: measuredHeight)
        }
    }

    private final class ComposerState: ObservableObject {
        @Published var text = ""
        @Published var hasVisibleContent = false
    }
}
#endif
