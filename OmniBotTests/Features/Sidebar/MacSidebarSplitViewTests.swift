#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Via_Vera

@Suite("Mac sidebar layout", .serialized)
@MainActor
struct MacSidebarSplitViewTests {
    @Test("Leading toolbar controls stay beside the window controls in every sidebar state")
    func keepsLeadingToolbarFixed() async throws {
        let model = Model()
        let window = makeWindow(model: model)
        defer { window.close() }
        try await waitForLayout(of: model, in: window)
        let initialFrames = try leadingFrames(in: window)
        #expect(initialFrames.count == 5)
        let zoomButton = try #require(window.standardWindowButton(.zoomButton))
        let windowControlsMaxX = zoomButton.convert(zoomButton.bounds, to: nil).maxX
        let firstFrame = try #require(initialFrames.first)
        #expect(firstFrame.minX > windowControlsMaxX)
        #expect(firstFrame.minX - windowControlsMaxX < 24)
        #expect(initialFrames.allSatisfy { $0.height >= 28 })

        for windowWidth in [1_180.0, 900, 700, MacSidebarLayout.minimumWidth] {
            window.setContentSize(NSSize(width: windowWidth, height: 700))
            for sidebarWidth in [AppDesign.sidebarMinimumWidth, AppDesign.sidebarMaximumWidth] {
                for isSidebarVisible in [false, true] {
                    model.sidebarWidth = sidebarWidth
                    model.isSidebarVisible = isSidebarVisible
                    try await waitForLayout(of: model, in: window)
                    try expectStableToolbar(in: window, model: model, matching: initialFrames)
                }
            }
        }

        // Settings recreate the group without its shared background, so AppKit spaces the
        // buttons apart, but all five stay visible, in order, from the same leading edge.
        model.isSettingsPresented = true
        try await waitForLayout(of: model, in: window)
        let settingsFrames = try leadingFrames(in: window)
        #expect(settingsFrames.count == 5)
        #expect(abs((settingsFrames.first?.minX ?? 0) - firstFrame.minX) < 0.5)
        #expect(zip(settingsFrames, settingsFrames.dropFirst()).allSatisfy { $0.maxX <= $1.minX })
        model.isSettingsPresented = false

        // The window cannot get narrower than a minimum-width sidebar beside a
        // minimum-width detail, so the toolbar keeps every control there too.
        window.setContentSize(NSSize(width: 400, height: 700))
        try await waitForLayout(of: model, in: window)
        #expect(abs(contentWidth(of: window) - MacSidebarLayout.minimumWidth) < 1)
        try expectStableToolbar(in: window, model: model, matching: initialFrames)
    }

    @Test("A narrow window shrinks the visible sidebar instead of clipping either pane")
    func fitsSidebarIntoNarrowWindows() async throws {
        let model = Model()
        model.sidebarWidth = AppDesign.sidebarMaximumWidth
        let window = makeWindow(model: model)
        defer { window.close() }

        for windowWidth in [1_000.0, 720, 660, MacSidebarLayout.minimumWidth] {
            window.setContentSize(NSSize(width: windowWidth, height: 700))
            try await waitForLayout(of: model, in: window)
            let width = contentWidth(of: window)
            #expect(model.sidebarFrame.minX >= -0.5)
            #expect(abs(model.sidebarFrame.width - MacSidebarLayout.fittedWidth(model.sidebarWidth, in: width)) < 0.5)
            #expect(model.detailFrame.maxX <= width + 0.5)
            #expect(model.detailFrame.width >= AppDesign.macDetailMinimumWidth - 0.5)
        }

        // The chosen width returns once the window has room again.
        window.setContentSize(NSSize(width: 1_000, height: 700))
        try await waitForLayout(of: model, in: window)
        #expect(abs(model.sidebarFrame.width - AppDesign.sidebarMaximumWidth) < 0.5)
        #expect(model.sidebarWidth == AppDesign.sidebarMaximumWidth)
    }

    @Test("Collapsing and expanding keeps the sidebar and detail content alive")
    func preservesContentAcrossToggles() async throws {
        let model = Model()
        let window = makeWindow(model: model)
        defer { window.close() }
        try await waitForLayout(of: model, in: window)
        #expect(model.sidebarAppearances == 1)
        #expect(model.detailAppearances == 1)

        for isSidebarVisible in [false, true, false, true] {
            model.isSidebarVisible = isSidebarVisible
            try await waitForLayout(of: model, in: window)
        }

        #expect(model.sidebarAppearances == 1)
        #expect(model.detailAppearances == 1)
        #expect(model.sidebarDisappearances == 0)
        #expect(model.detailDisappearances == 0)
    }

    @Test("The detail takes the sidebar's width only while the sidebar is shown")
    func resizesDetailWithSidebar() async throws {
        let model = Model()
        let window = makeWindow(model: model)
        defer { window.close() }
        window.setContentSize(NSSize(width: 1_000, height: 700))
        try await waitForLayout(of: model, in: window)
        #expect(abs(model.detailFrame.width - (1_000 - model.sidebarWidth)) < 0.5)
        #expect(abs(model.detailFrame.minX - model.sidebarWidth) < 0.5)

        model.isSidebarVisible = false
        try await waitForLayout(of: model, in: window)
        #expect(abs(model.detailFrame.width - 1_000) < 0.5)
        // The hidden sidebar sits entirely past the window's leading edge.
        #expect(model.sidebarFrame.maxX <= 0.5)
    }

    @Test("Resizing remembers the chosen width unless the shown width changes")
    func remembersChosenWidth() {
        // A narrow window shows a 360pt choice at 300pt. A click (no movement) or a drag
        // past what fits keeps the choice; narrowing what is shown replaces it.
        #expect(MacSidebarLayout.chosenWidth(after: 300, chosenWidth: 360, in: 700) == 360)
        #expect(MacSidebarLayout.chosenWidth(after: 340, chosenWidth: 360, in: 700) == 360)
        #expect(MacSidebarLayout.chosenWidth(after: 260, chosenWidth: 360, in: 700) == 260)
        #expect(MacSidebarLayout.chosenWidth(after: 320, chosenWidth: 300, in: 1_180) == 320)
        #expect(MacSidebarLayout.chosenWidth(after: 100, chosenWidth: 300, in: 1_180) == AppDesign.sidebarMinimumWidth)

        #expect(MacSidebarLayout.collapses(atWidth: AppDesign.sidebarMinimumWidth / 2 - 1))
        #expect(!MacSidebarLayout.collapses(atWidth: AppDesign.sidebarMinimumWidth / 2))
        #expect(!MacSidebarLayout.collapses(atWidth: AppDesign.sidebarMinimumWidth))
    }

    @Test("Sidebar widths stay in range and leave the detail its minimum width")
    func fitsSidebarWidth() {
        let roomy = 2_000.0
        #expect(MacSidebarLayout.fittedWidth(0, in: roomy) == AppDesign.sidebarMinimumWidth)
        #expect(MacSidebarLayout.fittedWidth(300, in: roomy) == 300)
        #expect(MacSidebarLayout.fittedWidth(10_000, in: roomy) == AppDesign.sidebarMaximumWidth)
        #expect(MacSidebarLayout.fittedWidth(360, in: 700) == 700 - AppDesign.macDetailMinimumWidth)
        #expect(MacSidebarLayout.fittedWidth(360, in: 500) == AppDesign.sidebarMinimumWidth)
        #expect(MacSidebarLayout.fittedWidth(300, in: .infinity) == 300)
    }

    // MARK: - Helpers

    private func expectStableToolbar(in window: NSWindow, model: Model, matching initialFrames: [NSRect]) throws {
        let toolbar = try #require(window.toolbar)
        let frames = try leadingFrames(in: window)
        #expect(frames.count == initialFrames.count)
        for (frame, initial) in zip(frames, initialFrames) {
            #expect(abs(frame.minX - initial.minX) < 0.5)
            #expect(abs(frame.width - initial.width) < 0.5)
            #expect(abs(frame.height - initial.height) < 0.5)
        }
        #expect(toolbar.items.filter(\.isNavigational).last?.label == model.sidebarToggleTitle)
        #expect(!toolbar.items.contains { $0.itemIdentifier.rawValue.hasSuffix("toggleSidebar") })
        #expect(!toolbar.items.contains { $0 is NSTrackingSeparatorToolbarItem })

        // The title follows the leading controls directly.
        let lastLeadingFrame = try #require(frames.last)
        let title = try #require(titleField(in: window))
        let titleGap = title.convert(title.bounds, to: nil).minX - lastLeadingFrame.maxX
        #expect(titleGap >= 0 && titleGap < 20)

        let more = try #require(toolbar.items.first { $0.label == "More" })
        let moreView = try #require(more.view)
        #expect(moreView.window != nil)
        #expect(moreView.convert(moreView.bounds, to: nil).maxX > contentWidth(of: window) - 16)
    }

    private func leadingFrames(in window: NSWindow) throws -> [NSRect] {
        let items = try #require(window.toolbar).items.filter(\.isNavigational)
        return try items.map { item in
            // An item without a view in the window has moved into the overflow menu.
            let view = try #require(item.view)
            try #require(view.window != nil)
            return view.convert(view.bounds, to: nil)
        }
    }

    private func isToolbarReady(in window: NSWindow, model: Model) -> Bool {
        guard let items = window.toolbar?.items.filter(\.isNavigational), items.count == 5 else { return false }
        return items.allSatisfy { $0.view?.window != nil } && items.last?.label == model.sidebarToggleTitle
    }

    private func titleField(in window: NSWindow) -> NSTextField? {
        func search(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.stringValue == Fixture.title,
               !field.isHiddenOrHasHiddenAncestor {
                return field
            }
            return view.subviews.lazy.compactMap(search).first
        }
        return window.contentView?.superview.flatMap(search)
    }

    private func contentWidth(of window: NSWindow) -> Double {
        Double(window.contentView?.bounds.width ?? 0)
    }

    /// Waits until SwiftUI has laid out exactly the current model state and the toolbar
    /// reflects it, then lays out the window so toolbar frames are current.
    private func waitForLayout(of model: Model, in window: NSWindow) async throws {
        let isLaidOut = await waitUntil {
            let width = contentWidth(of: window)
            let sidebarWidth = MacSidebarLayout.fittedWidth(model.sidebarWidth, in: width)
            let visibleWidth = model.isSidebarVisible ? sidebarWidth : 0
            return abs(model.sidebarFrame.width - sidebarWidth) < 0.5
                && abs(model.sidebarFrame.maxX - visibleWidth) < 0.5
                && abs(model.detailFrame.minX - visibleWidth) < 0.5
                && abs(model.detailFrame.maxX - width) < 0.5
                && isToolbarReady(in: window, model: model)
        }
        try #require(isLaidOut)
        window.layoutIfNeeded()
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func makeWindow(model: Model) -> NSWindow {
        let controller = NSHostingController(rootView: Fixture(model: model))
        controller.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 1_180, height: 700))
        // AppKit only lays out the toolbar of an ordered window; keep it invisible.
        window.alphaValue = 0
        window.orderFront(nil)
        return window
    }

    @MainActor @Observable
    final class Model {
        var isSidebarVisible = true
        var isSettingsPresented = false
        var sidebarWidth = AppDesign.sidebarIdealWidth
        var sidebarFrame = CGRect.zero
        var detailFrame = CGRect.zero
        var sidebarAppearances = 0
        var sidebarDisappearances = 0
        var detailAppearances = 0
        var detailDisappearances = 0

        var sidebarToggleTitle: String {
            isSidebarVisible ? String(localized: "隐藏边栏") : String(localized: "显示边栏")
        }
    }

    private struct Fixture: View {
        static let title = "Conversation title"
        @Bindable var model: Model

        var body: some View {
            MacSidebarSplitView(
                isSidebarVisible: model.isSidebarVisible,
                sidebarWidth: $model.sidebarWidth,
                collapseSidebar: { model.isSidebarVisible = false }
            ) {
                Text("Sidebar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.bar)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.sidebarFrame = $0 }
                    .onAppear { model.sidebarAppearances += 1 }
                    .onDisappear { model.sidebarDisappearances += 1 }
            } detail: {
                Text("Detail")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.detailFrame = $0 }
                    .onAppear { model.detailAppearances += 1 }
                    .onDisappear { model.detailDisappearances += 1 }
                    .navigationTitle(Self.title)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu("More", systemImage: "ellipsis") {
                                Button("Action") {}
                            }
                            .menuIndicator(.hidden)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
            }
            .toolbar {
                MacWindowNavigationControls(
                    canGoBack: false,
                    canGoForward: false,
                    isSettingsPresented: model.isSettingsPresented,
                    isSidebarVisible: model.isSidebarVisible,
                    showSettings: {},
                    goBack: {},
                    goForward: {},
                    newConversation: {},
                    toggleSidebar: { model.isSidebarVisible.toggle() }
                )
            }
        }
    }
}
#endif
