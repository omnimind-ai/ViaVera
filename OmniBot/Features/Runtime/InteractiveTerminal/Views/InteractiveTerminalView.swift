import SwiftUI

struct InteractiveTerminalView: View {
    let model: InteractiveTerminalModel
#if os(macOS)
    let isKeyboardFocused: FocusState<Bool>.Binding
#endif

    var body: some View {
        VStack(spacing: 0) {
#if os(iOS)
            Group {
                if let terminalView = model.nativeTerminalView {
                    ISHUpstreamTerminalViewRepresentable(
                        terminalView: terminalView,
                        focusRequestID: model.keyboardFocusRequestID
                    )
                } else {
                    Color.clear
                }
            }
                .overlay {
                    if model.state.showsBlockingOverlay {
                        TerminalStateOverlay(state: model.state, retry: model.startNewSession)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppDesign.chatBackground)
                            .padding(AppDesign.contentPadding)
                    }
                }
#else
            TerminalScreenView(
                text: model.displayText,
                state: model.state,
                onViewportChange: model.updateViewport,
                retry: model.startNewSession
            )

            TerminalKeyboardInput(
                model: model,
                isFocused: isKeyboardFocused
            )
#endif

#if os(iOS)
            TerminalAccessoryKeyBar(model: model)
#endif
        }
#if os(iOS)
        .background(AppDesign.chatBackground)
#endif
        .task {
            guard model.state == .idle else { return }
            // Keep Alpine startup, PTY output, and viewport changes out of the
            // initial terminal layout transaction.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await model.startIfNeeded()
        }
        .task(id: model.state.acceptsInput) {
            guard model.state.acceptsInput else {
#if os(macOS)
                isKeyboardFocused.wrappedValue = false
#endif
                return
            }

            // Install keyboard input only after the terminal layout
            // and first terminal render have settled.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, model.state.acceptsInput else { return }
#if os(iOS)
            model.requestKeyboardFocus()
#else
            isKeyboardFocused.wrappedValue = true
#endif
        }
        .onDisappear {
#if os(macOS)
            isKeyboardFocused.wrappedValue = false
#endif
        }
    }
}
