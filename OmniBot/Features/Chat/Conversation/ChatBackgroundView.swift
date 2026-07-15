import SwiftUI

struct ChatBackgroundView: View {
    let settings: AppearanceSettingsModel

    var body: some View {
        ZStack {
            AppDesign.chatBackground

            if let backgroundImage = settings.backgroundImage {
                Image(decorative: backgroundImage, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .brightness(settings.backgroundBrightness)
                    .blur(radius: settings.backgroundBlur, opaque: true)
                    .opacity(settings.backgroundOpacity)
                    .clipped()
            }
        }
    }
}
