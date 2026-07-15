#if os(macOS)
import SwiftUI

struct SettingsOverlayView: View {
    let initialDestination: SettingsCardDestination
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Button(action: onDismiss) {
                    Color.black.opacity(0.18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭设置")
                .ignoresSafeArea()

                SettingsCardView(initialDestination: initialDestination)
                    .frame(
                        width: cardWidth(in: proxy.size),
                        height: cardHeight(in: proxy.size)
                    )
                    .background(
                        .background,
                        in: .rect(cornerRadius: AppDesign.settingsOverlayCornerRadius)
                    )
                    .clipShape(.rect(cornerRadius: AppDesign.settingsOverlayCornerRadius))
                    .shadow(radius: 24, y: 12)
                    .offset(
                        y: (proxy.safeAreaInsets.bottom - proxy.safeAreaInsets.top) / 2
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onExitCommand(perform: onDismiss)
    }

    private func cardWidth(in containerSize: CGSize) -> Double {
        min(
            AppDesign.settingsWindowIdealWidth,
            max(containerSize.width - AppDesign.settingsOverlayInset * 2, 0)
        )
    }

    private func cardHeight(in containerSize: CGSize) -> Double {
        min(
            AppDesign.settingsWindowIdealHeight,
            max(containerSize.height - AppDesign.settingsOverlayInset * 2, 0)
        )
    }
}
#endif
