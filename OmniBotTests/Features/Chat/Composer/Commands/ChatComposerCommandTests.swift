import Testing
@testable import Via_Vera

@Suite("Chat composer commands")
struct ChatComposerCommandTests {
    @Test("Parses compact and supported effort commands")
    func parsesCommands() {
        #expect(ChatComposerCommand.parse(" /compact ") == .compact)
        #expect(ChatComposerCommand.parse("/compact now") == .compact)
        #expect(ChatComposerCommand.parse("/effort") == .showEffort)
        #expect(ChatComposerCommand.parse("/effort NO") == .setEffort(.no))
        #expect(ChatComposerCommand.parse("/effort xhigh") == .setEffort(.xhigh))
        #expect(ChatComposerCommand.parse("/effort max") == .setEffort(.max))
        #expect(ChatComposerCommand.parse("/effort medium") == .invalidEffort)
        #expect(ChatComposerCommand.parse("regular message") == nil)
    }
}
