import SwiftUI

struct ChatMoreMenu: View {
    let openBrowser: () -> Void
    let openWorkspace: () -> Void
    let openSettings: () -> Void

    var body: some View {
        Menu {
            Button("浏览器", systemImage: "safari", action: openBrowser)
            Button("工作区", systemImage: "folder", action: openWorkspace)
            Button("设置", systemImage: "gearshape", action: openSettings)
        } label: {
            Label("更多", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
#if !os(macOS)
                .frame(
                    minWidth: AppDesign.minimumTouchTarget,
                    minHeight: AppDesign.minimumTouchTarget
                )
#endif
        }
        .menuIndicator(.hidden)
#if os(macOS)
        .foregroundStyle(.secondary)
        .composerControlFrame()
        .buttonStyle(.borderless)
#endif
        .accessibilityLabel("更多")
    }
}
