import SwiftUI

struct SidebarConversationAvatar: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.body)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: .circle)
            .accessibilityHidden(true)
    }
}
