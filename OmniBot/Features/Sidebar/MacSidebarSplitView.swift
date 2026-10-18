#if os(macOS)
import SwiftUI

enum MacSidebarLayout {
    /// A minimum-width sidebar always fits beside a minimum-width detail, which also
    /// leaves room for every window toolbar control.
    static let minimumWidth = AppDesign.sidebarMinimumWidth + AppDesign.macDetailMinimumWidth

    /// The sidebar width that fits the supported range and leaves the detail its minimum.
    static func fittedWidth(_ width: Double, in availableWidth: Double) -> Double {
        let maximumWidth = max(
            AppDesign.sidebarMinimumWidth,
            min(AppDesign.sidebarMaximumWidth, availableWidth - AppDesign.macDetailMinimumWidth)
        )
        return min(max(width, AppDesign.sidebarMinimumWidth), maximumWidth)
    }

    /// The width to remember after a resize. A narrow window shows the sidebar narrower
    /// than chosen, so a resize that leaves the shown width unchanged keeps the choice.
    static func chosenWidth(after proposedWidth: Double, chosenWidth: Double, in availableWidth: Double) -> Double {
        let newWidth = fittedWidth(proposedWidth, in: availableWidth)
        return newWidth == fittedWidth(chosenWidth, in: availableWidth) ? chosenWidth : newWidth
    }

    /// Like a native sidebar, letting go far past the minimum width collapses it.
    static func collapses(atWidth width: Double) -> Bool {
        width < AppDesign.sidebarMinimumWidth / 2
    }
}

/// Shows the sidebar beside the detail inside the window content. AppKit lays out the
/// window title and leading toolbar items after a split-view sidebar, so they would
/// follow its divider; a window-wide toolbar keeps them next to the window controls.
struct MacSidebarSplitView<Sidebar: View, Detail: View>: View {
    let isSidebarVisible: Bool
    /// The width the person chose. A narrow window shows the sidebar narrower without
    /// changing it, so the chosen width returns once the window is wide again.
    @Binding var sidebarWidth: Double
    let collapseSidebar: () -> Void
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail
    @State private var availableWidth = Double.infinity
    // Ease back when a drag is cancelled or collapses the sidebar.
    @GestureState(resetTransaction: Transaction(animation: .smooth(duration: 0.25)))
    private var dragTranslation: Double = 0

    var body: some View {
        let width = MacSidebarLayout.fittedWidth(restingWidth + dragTranslation, in: availableWidth)

        HStack(spacing: 0) {
            sidebar
                .frame(width: width)
                .frame(maxHeight: .infinity)
                // Collapsing slides the full-width sidebar past the window's leading edge,
                // so its content keeps its layout and state while hidden.
                .frame(width: isSidebarVisible ? width : 0, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    MacSidebarDivider(width: width, resize: resize(to:))
                        .gesture(resizeGesture)
                }
                .allowsHitTesting(isSidebarVisible)
                .accessibilityHidden(!isSidebarVisible)
                // Keep the divider's hit area above the detail's leading edge.
                .zIndex(1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: MacSidebarLayout.minimumWidth)
        .onGeometryChange(for: Double.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
    }

    /// The width the sidebar shows while its divider is not being dragged.
    private var restingWidth: Double {
        MacSidebarLayout.fittedWidth(sidebarWidth, in: availableWidth)
    }

    private var resizeGesture: some Gesture {
        // Global coordinates stay stable while the divider moves under the pointer. The
        // live width is gesture state, so the chosen width changes only when a drag ends.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($dragTranslation) { value, translation, _ in
                translation = value.translation.width
            }
            .onEnded { value in
                let proposedWidth = restingWidth + value.translation.width
                // A collapsed sidebar keeps its width for the next time it is shown.
                if MacSidebarLayout.collapses(atWidth: proposedWidth) {
                    collapseSidebar()
                } else {
                    resize(to: proposedWidth)
                }
            }
    }

    private func resize(to proposedWidth: Double) {
        let width = MacSidebarLayout.chosenWidth(after: proposedWidth, chosenWidth: sidebarWidth, in: availableWidth)
        if width != sidebarWidth { sidebarWidth = width }
    }
}

struct MacSidebarDivider: View {
    let width: Double
    let resize: (Double) -> Void

    private static let accessibilityStep: Double = 20

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .overlay {
                // Match the native divider's hit area, which is wider than its hairline,
                // and keep most of it off the sidebar's scroller.
                Color.clear
                    .frame(width: 9)
                    .contentShape(.rect)
                    .offset(x: 3)
                    .pointerStyle(.columnResize)
            }
            .accessibilityElement()
            .accessibilityLabel("边栏宽度")
            .accessibilityValue(Text(width, format: .number.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: resize(width + Self.accessibilityStep)
                case .decrement: resize(width - Self.accessibilityStep)
                @unknown default: break
                }
            }
    }
}
#endif
