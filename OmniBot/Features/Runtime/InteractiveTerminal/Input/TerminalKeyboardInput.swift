import SwiftUI

struct TerminalKeyboardInput: View {
    private static let sentinel = "\u{200B}"
#if os(macOS)
    private static let deleteForwardSequence = Data([0x1B, 0x5B, 0x33, 0x7E])
    private static let terminalKeys: [KeyEquivalent: TerminalKey] = [
        .upArrow: .arrowUp,
        .downArrow: .arrowDown,
        .leftArrow: .arrowLeft,
        .rightArrow: .arrowRight,
        .escape: .escape,
        .delete: .backspace,
        .home: .home,
        .end: .end,
        .pageUp: .pageUp,
        .pageDown: .pageDown,
        .tab: .tab,
    ]
#endif

    let model: InteractiveTerminalModel
    let isFocused: FocusState<Bool>.Binding

    @State private var buffer = Self.sentinel

    var body: some View {
        TextField("终端输入", text: $buffer)
            .focused(isFocused)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
#endif
            .submitLabel(.return)
            .onSubmit(sendReturn)
            .onChange(of: buffer, handleBufferChange)
#if os(macOS)
            .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
#endif
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .accessibilityHidden(true)
    }

    private func handleBufferChange(_ oldValue: String, _ newValue: String) {
        guard newValue != Self.sentinel else { return }

        if newValue.isEmpty {
            model.send(.backspace)
        } else {
            let input = newValue.replacing(Self.sentinel, with: "")
            if !input.isEmpty {
                model.send(input)
            }
        }
        buffer = Self.sentinel
    }

    private func sendReturn() {
        model.send(.enter)
        buffer = Self.sentinel
        isFocused.wrappedValue = true
    }

#if os(macOS)
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard model.state.acceptsInput else { return .ignored }
        guard !keyPress.modifiers.contains(.command) else { return .ignored }

        if keyPress.key == .deleteForward {
            model.sendTerminalInput(Self.deleteForwardSequence)
            return .handled
        }

        if let terminalKey = Self.terminalKeys[keyPress.key] {
            model.send(terminalKey)
            return .handled
        }

        let usesControl = keyPress.modifiers.contains(.control)
        let usesAlternate = keyPress.modifiers.contains(.option)
        guard usesControl || usesAlternate else { return .ignored }

        var modifiers = TerminalModifierState()
        if usesControl {
            modifiers.toggleControl()
        }
        if usesAlternate {
            modifiers.toggleAlternate()
        }
        model.sendTerminalInput(
            TerminalKeyEncoder.data(
                for: String(keyPress.key.character),
                modifiers: modifiers
            )
        )
        return .handled
    }
#endif
}
