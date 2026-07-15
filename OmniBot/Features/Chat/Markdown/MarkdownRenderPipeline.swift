import Foundation

actor MarkdownRenderPipeline {
    func render(_ markdown: String) -> [MarkdownBlock] {
        // Markdown parsing stays off the main actor; only the finished value reaches SwiftUI.
        MarkdownBlockParser.parse(markdown)
    }
}
