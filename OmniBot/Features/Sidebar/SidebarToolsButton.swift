#if os(macOS)
import SwiftUI

struct SidebarToolsButton: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button(action: appModel.openNativeToolLibrary) {
            Label("我的工具", systemImage: "square.grid.2x2")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppDesign.compactSpacing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .background(
            appModel.destination == .tools ? AppDesign.sidebarSelectionBackground : .clear,
            in: .rect(cornerRadius: AppDesign.compactCornerRadius)
        )
        .accessibilityAddTraits(appModel.destination == .tools ? .isSelected : [])
        .padding(.horizontal, AppDesign.sidebarHorizontalInset)
        .padding(.bottom, AppDesign.standardSpacing)
    }
}
#endif
