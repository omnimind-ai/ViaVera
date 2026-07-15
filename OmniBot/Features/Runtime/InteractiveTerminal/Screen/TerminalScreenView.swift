import SwiftUI

struct TerminalScreenView: View {
    let text: String
    let state: InteractiveTerminalState
    let onViewportChange: (TerminalViewportSize) -> Void
    let retry: () -> Void

    @State private var measuredViewport = TerminalViewportSize()

    @ScaledMetric(relativeTo: .body)
    private var characterWidth = AppDesign.terminalEstimatedCharacterWidth

    @ScaledMetric(relativeTo: .body)
    private var lineHeight = AppDesign.terminalEstimatedLineHeight

    var body: some View {
        let measuredCharacterWidth = characterWidth
        let measuredLineHeight = lineHeight
        let horizontalInsets = AppDesign.terminalScreenHorizontalPadding * 2
        let verticalInsets = AppDesign.terminalScreenVerticalPadding * 2

        ScrollView(.vertical) {
            Text(text.isEmpty ? " " : text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, AppDesign.terminalScreenHorizontalPadding)
                .padding(.vertical, AppDesign.terminalScreenVerticalPadding)
        }
        .defaultScrollAnchor(.top, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .defaultScrollAnchor(.top, for: .alignment)
        .scrollDismissesKeyboard(.immediately)
        .onGeometryChange(for: TerminalViewportSize.self) { proxy in
            let size = proxy.size
            let columns = Int(
                max(size.width - horizontalInsets, measuredCharacterWidth)
                    / measuredCharacterWidth
            )
            let rows = Int(
                max(size.height - verticalInsets, measuredLineHeight)
                    / measuredLineHeight
            )
            return TerminalViewportSize(columns: columns, rows: rows)
        } action: { newViewport in
            measuredViewport = newViewport
        }
        .task(id: measuredViewport) {
            // Keyboard presentation animates through many intermediate
            // heights. Apply only the settled viewport so resizing the PTY
            // cannot feed a new observable render back into that animation.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            onViewportChange(measuredViewport)
        }
        .overlay {
            if state.showsBlockingOverlay {
                TerminalStateOverlay(state: state, retry: retry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.bar)
                    .padding(AppDesign.contentPadding)
            }
        }
    }
}
