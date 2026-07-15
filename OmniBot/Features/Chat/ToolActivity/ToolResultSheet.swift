import SwiftUI

struct ToolResultSheet: View {
    let tool: ToolCallPresentation

    var body: some View {
#if os(macOS)
        ToolResultContentView(tool: tool, showsTitle: true)
            .frame(width: AppDesign.toolResultPopoverWidth)
            .frame(
                minHeight: AppDesign.toolResultPopoverMinimumHeight,
                idealHeight: AppDesign.toolResultPopoverIdealHeight,
                maxHeight: AppDesign.toolResultPopoverMaximumHeight
            )
#else
        NavigationStack {
            ToolResultContentView(tool: tool, showsTitle: false)
                .navigationTitle(tool.title)
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }
}
