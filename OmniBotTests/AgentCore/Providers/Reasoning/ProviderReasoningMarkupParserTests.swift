import Testing
@testable import Via_Vera

@Suite("Provider reasoning markup parser")
struct ProviderReasoningMarkupParserTests {
    @Test("Think blocks are separated from visible answer content")
    func separatesThinkBlocks() {
        let result = ProviderReasoningMarkupParser.parse(
            "Intro <think>first step</think>Answer<think>second step</think>."
        )

        #expect(result.content == "Intro Answer.")
        #expect(result.reasoning == "first stepsecond step")
    }

    @Test("Tag matching is case insensitive")
    func matchesTagsCaseInsensitively() {
        let result = ProviderReasoningMarkupParser.parse(
            "<THINK>Reasoning</ThInK>Answer"
        )

        #expect(result.content == "Answer")
        #expect(result.reasoning == "Reasoning")
    }

    @Test("Streaming parse withholds an incomplete opening tag")
    func withholdsIncompleteOpeningTag() {
        let streaming = ProviderReasoningMarkupParser.parse(
            "Visible<thi",
            isFinal: false
        )
        let final = ProviderReasoningMarkupParser.parse(
            "Visible<thi",
            isFinal: true
        )

        #expect(streaming.content == "Visible")
        #expect(streaming.reasoning.isEmpty)
        #expect(final.content == "Visible<thi")
    }

    @Test("Streaming parse withholds an incomplete closing tag")
    func withholdsIncompleteClosingTag() {
        let streaming = ProviderReasoningMarkupParser.parse(
            "<think>Reasoning</thin",
            isFinal: false
        )
        let completed = ProviderReasoningMarkupParser.parse(
            "<think>Reasoning</think>Answer",
            isFinal: false
        )

        #expect(streaming.content.isEmpty)
        #expect(streaming.reasoning == "Reasoning")
        #expect(completed.content == "Answer")
        #expect(completed.reasoning == "Reasoning")
    }

    @Test("Final parse keeps an unclosed think block as reasoning")
    func finalUnclosedThinkBlock() {
        let result = ProviderReasoningMarkupParser.parse(
            "Before<think>unfinished reasoning"
        )

        #expect(result.content == "Before")
        #expect(result.reasoning == "unfinished reasoning")
    }

    @Test("An orphan closing tag keeps its leading text out of the answer")
    func orphanClosingTagTreatsLeadingTextAsReasoning() {
        let result = ProviderReasoningMarkupParser.parse(
            "private reasoning</think>Visible answer"
        )

        #expect(result.reasoning == "private reasoning")
        #expect(result.content == "Visible answer")
    }
}
