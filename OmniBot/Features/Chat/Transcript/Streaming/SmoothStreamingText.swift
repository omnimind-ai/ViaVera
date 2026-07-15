import SwiftUI

struct SmoothStreamingText: View {
    let text: String
    let isStreaming: Bool

    @State private var targetText: String
    @State private var targetRevision = 0
    @State private var renderedRevision = -1
    @State private var blocks: [MarkdownBlock] = []
    @State private var renderPipeline = MarkdownRenderPipeline()

    init(text: String, isStreaming: Bool) {
        self.text = text
        self.isStreaming = isStreaming
        _targetText = State(initialValue: text)
    }

    var body: some View {
        MarkdownContentView(blocks: blocks)
            .onChange(of: text) { _, newValue in
                targetText = newValue
                targetRevision &+= 1
            }
            .task(id: isStreaming) {
                if isStreaming {
                    await renderStreamingText()
                } else {
                    await renderFinalText(text)
                }
            }
    }

    @MainActor
    private func renderStreamingText() async {
        while !Task.isCancelled {
            if renderedRevision != targetRevision {
                let snapshot = targetText
                let revision = targetRevision
                blocks = await renderPipeline.render(snapshot)
                renderedRevision = revision
            }

            do {
                try await Task.sleep(for: streamingRenderInterval)
            } catch {
                return
            }
        }
    }

    @MainActor
    private func renderFinalText(_ source: String) async {
        blocks = await renderPipeline.render(source)
        renderedRevision = targetRevision
    }

    private var streamingRenderInterval: Duration {
        // Coalesce token snapshots so parsing work cannot grow with provider event frequency.
        targetText.utf8.count > 100_000 ? .milliseconds(140) : .milliseconds(70)
    }
}
