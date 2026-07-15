import SwiftUI

#if os(iOS)
struct UserMessageEditButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif
