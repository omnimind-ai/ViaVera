import Foundation
import Testing
@testable import Via_Vera

@Suite("Sidebar conversation avatar palette")
@MainActor
struct SidebarConversationAvatarPaletteTests {
    @Test("Conversation colors are stable, bounded, and varied")
    func stableColorIndex() throws {
        let first = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let second = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )

        let firstIndex = SidebarConversationAvatarPalette.colorIndex(for: first)
        let repeatedIndex = SidebarConversationAvatarPalette.colorIndex(for: first)
        let secondIndex = SidebarConversationAvatarPalette.colorIndex(for: second)

        #expect(firstIndex == repeatedIndex)
        #expect((0 ..< SidebarConversationAvatarPalette.colorCount).contains(firstIndex))
        #expect((0 ..< SidebarConversationAvatarPalette.colorCount).contains(secondIndex))
        #expect(firstIndex != secondIndex)
    }
}
