import SwiftUI

struct PacedReasoningText: View {
    let text: String
    let isStreaming: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedText = ""
    @State private var targetText: String

    init(text: String, isStreaming: Bool) {
        self.text = text
        self.isStreaming = isStreaming
        _targetText = State(initialValue: text)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollAnchor.bottom)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: displayedText.count) {
                guard isStreaming else { return }
                proxy.scrollTo(ScrollAnchor.bottom, anchor: .bottom)
            }
        }
        .frame(maxHeight: 210)
        .accessibilityHidden(isStreaming)
        .onChange(of: text) { _, text in
            targetText = text
            if !isStreaming || reduceMotion {
                displayedText = text
            }
        }
        .task(id: RevealMode(
            isStreaming: isStreaming,
            reduceMotion: reduceMotion
        )) {
            await revealText()
        }
    }

    @MainActor
    private func revealText() async {
        guard isStreaming, !reduceMotion else {
            targetText = text
            displayedText = text
            return
        }

        while !Task.isCancelled {
            if !targetText.hasPrefix(displayedText) {
                displayedText = targetText
            } else if displayedText.count < targetText.count {
                let backlog = targetText.count - displayedText.count
                let step = backlog > 20 ? min(4, max(2, backlog / 20)) : 1
                displayedText = String(
                    targetText.prefix(min(targetText.count, displayedText.count + step))
                )
            }
            do {
                try await Task.sleep(for: .milliseconds(30))
            } catch {
                return
            }
        }
    }

    private struct RevealMode: Hashable {
        let isStreaming: Bool
        let reduceMotion: Bool
    }

    private enum ScrollAnchor: Hashable {
        case bottom
    }
}
