import SwiftUI

extension View {
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .environment(\.defaultMinListRowHeight, AppDesign.settingsInputMinimumHeight)
    }

    func settingsInputStyle(
        minimumHeight: Double = AppDesign.settingsInputMinimumHeight,
        alignment: Alignment = .leading
    ) -> some View {
#if os(iOS)
        textFieldStyle(.plain)
            .padding(.horizontal, AppDesign.settingsInputHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: alignment)
            .background(Color("SettingsInputBackground"), in: Capsule())
            .contentShape(Capsule())
#else
        textFieldStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: alignment)
            .contentShape(Rectangle())
#endif
    }

    func settingsMultilineInputStyle(
        minimumHeight: Double,
        maximumHeight: CGFloat? = nil,
        alignment: Alignment = .topLeading
    ) -> some View {
        textFieldStyle(.plain)
            .frame(
                maxWidth: .infinity,
                minHeight: minimumHeight,
                maxHeight: maximumHeight,
                alignment: alignment
            )
            .contentShape(Rectangle())
    }
}
