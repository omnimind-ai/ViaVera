import SwiftUI

enum SidebarConversationAvatarPalette {
    static let colorCount = 8

    private static let colors: [Color] = [
        .blue,
        .indigo,
        .purple,
        .pink,
        .orange,
        .teal,
        .green,
        .cyan,
    ]

    static func color(for conversationID: UUID) -> Color {
        colors[colorIndex(for: conversationID)]
    }

    static func colorIndex(for conversationID: UUID) -> Int {
        var rawUUID = conversationID.uuid
        var hash: UInt64 = 14_695_981_039_346_656_037
        withUnsafeBytes(of: &rawUUID) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return Int(hash % UInt64(colorCount))
    }
}
