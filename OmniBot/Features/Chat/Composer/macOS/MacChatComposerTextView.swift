#if os(macOS)
import SwiftUI

struct MacChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: Double
    @Binding var isFocused: Bool
    @Binding var hasVisibleContent: Bool

    let isEnabled: Bool
    let maximumLines: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ComposerScrollView {
        let scrollView = ComposerScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = ComposerNativeTextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.submit()
        }
        textView.onWindowChange = { [weak coordinator = context.coordinator] in
            coordinator?.updateFocus()
        }
        textView.onTextPresentationChange = { [weak coordinator = context.coordinator] in
            coordinator?.updateTextPresentation()
        }

        scrollView.documentView = textView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleHeightUpdate()
        }
        context.coordinator.scrollView = scrollView
        context.coordinator.scheduleHeightUpdate()
        return scrollView
    }

    func updateNSView(_ scrollView: ComposerScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ComposerNativeTextView else { return }

        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.submit()
        }
        textView.onWindowChange = { [weak coordinator = context.coordinator] in
            coordinator?.updateFocus()
        }
        textView.onTextPresentationChange = { [weak coordinator = context.coordinator] in
            coordinator?.updateTextPresentation()
        }
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled

        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        }

        context.coordinator.updateFocus()
        context.coordinator.scheduleTextPresentationUpdate()
        context.coordinator.scheduleHeightUpdate()
    }
}

extension MacChatComposerTextView {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacChatComposerTextView
        weak var scrollView: ComposerScrollView?
        private var synchronizedFocus = false

        init(parent: MacChatComposerTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            updateBindingFromNativeFocus(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            updateBindingFromNativeFocus(false)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // AppKit may deliver the first text change before its begin-editing
            // notification. Record the native focus before updating SwiftUI so
            // that the following representable refresh cannot resign it.
            if textView.window?.firstResponder === textView {
                updateBindingFromNativeFocus(true)
            }
            updateTextPresentation()
            if !textView.hasMarkedText(), parent.text != textView.string {
                parent.text = textView.string
            }
            scheduleHeightUpdate()
        }

        func submit() {
            parent.onSubmit()
        }

        func updateFocus() {
            guard let textView = scrollView?.documentView as? ComposerNativeTextView,
                  let window = textView.window else {
                return
            }

            let requestedFocus = parent.isFocused && parent.isEnabled
            guard requestedFocus != synchronizedFocus else { return }

            if requestedFocus {
                if window.firstResponder !== textView {
                    guard window.makeFirstResponder(textView) else { return }
                }
            } else if window.firstResponder === textView {
                guard window.makeFirstResponder(nil) else { return }
            }
            synchronizedFocus = requestedFocus
        }

        private func updateBindingFromNativeFocus(_ isFocused: Bool) {
            synchronizedFocus = isFocused
            if parent.isFocused != isFocused {
                parent.isFocused = isFocused
            }
        }

        func updateTextPresentation() {
            guard let textView = scrollView?.documentView as? ComposerNativeTextView else {
                return
            }
            if parent.hasVisibleContent != textView.hasVisibleContent {
                parent.hasVisibleContent = textView.hasVisibleContent
            }
        }

        func scheduleTextPresentationUpdate() {
            Task { @MainActor [weak self] in
                self?.updateTextPresentation()
            }
        }

        func scheduleHeightUpdate() {
            Task { @MainActor [weak self] in
                self?.updateHeight()
            }
        }

        private func updateHeight() {
            guard let scrollView,
                  let textView = scrollView.documentView as? ComposerNativeTextView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else {
                return
            }

            let availableWidth = max(scrollView.contentSize.width, 1)
            if textContainer.containerSize.width != availableWidth {
                textContainer.containerSize = NSSize(
                    width: availableWidth,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
            layoutManager.ensureLayout(for: textContainer)

            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            let lineHeight = layoutManager.defaultLineHeight(for: font)
            let verticalInsets = textView.textContainerInset.height * 2
            let contentHeight = max(
                lineHeight + verticalInsets,
                ceil(layoutManager.usedRect(for: textContainer).height) + verticalInsets
            )
            let maximumHeight = ceil(lineHeight * Double(parent.maximumLines) + verticalInsets)
            let targetHeight = min(
                max(contentHeight, AppDesign.composerTextLineHeight),
                maximumHeight
            )
            let needsScroller = contentHeight > maximumHeight + 0.5
            let documentSize = NSSize(
                width: availableWidth,
                height: max(contentHeight, scrollView.contentSize.height)
            )

            if scrollView.hasVerticalScroller != needsScroller {
                scrollView.hasVerticalScroller = needsScroller
            }
            if abs(textView.frame.width - documentSize.width) > 0.5
                || abs(textView.frame.height - documentSize.height) > 0.5 {
                textView.setFrameSize(documentSize)
            }
            if abs(parent.measuredHeight - targetHeight) > 0.5 {
                parent.measuredHeight = targetHeight
            }
            if needsScroller {
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
    }

    final class ComposerScrollView: NSScrollView {
        var onLayout: (() -> Void)?

        override func layout() {
            super.layout()
            onLayout?()
        }
    }

    final class ComposerNativeTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var onWindowChange: (() -> Void)?
        var onTextPresentationChange: (() -> Void)?

        var hasVisibleContent: Bool {
            !string.isEmpty || hasMarkedText()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?()
        }

        override func setMarkedText(
            _ string: Any,
            selectedRange: NSRange,
            replacementRange: NSRange
        ) {
            super.setMarkedText(
                string,
                selectedRange: selectedRange,
                replacementRange: replacementRange
            )
            onTextPresentationChange?()
        }

        override func unmarkText() {
            super.unmarkText()
            onTextPresentationChange?()
        }

        override func keyDown(with event: NSEvent) {
            guard isReturn(event), !hasMarkedText() else {
                super.keyDown(with: event)
                return
            }

            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                insertText("\n", replacementRange: selectedRange())
                return
            }

            onSubmit?()
        }

        private func isReturn(_ event: NSEvent) -> Bool {
            event.keyCode == 36
                || event.keyCode == 76
                || event.charactersIgnoringModifiers == "\r"
                || event.charactersIgnoringModifiers == "\n"
        }
    }
}
#endif
