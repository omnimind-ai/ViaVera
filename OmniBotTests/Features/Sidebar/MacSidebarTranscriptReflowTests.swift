#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Via_Vera

@Suite("Mac sidebar transcript reflow", .serialized)
@MainActor
struct MacSidebarTranscriptReflowTests {
    @Test("Sidebar animation does not repeatedly resize the lazy transcript", arguments: [700.0, 1_000, 1_400])
    func reflowsAtFinalWidth(windowWidth: Double) async throws {
        let model = Model()
        let window = makeWindow(model: model, width: windowWidth)
        defer { window.close() }
        try await settle()
        try #require(model.samples.last != nil)
        #expect(model.detailAppearances == 1)

        for visible in [true, false, true] {
            let initial = try #require(model.samples.last)
            model.samples.removeAll()
            model.sidebarEdges.removeAll()
            model.sidebarAnimationTransactions.removeAll()
            withAnimation(.smooth(duration: 0.25)) {
                model.isSidebarVisible = visible
            }
            try await settle()

            let final = try #require(model.samples.last)
            let widthChange = visible ? -model.sidebarWidth : model.sidebarWidth
            #expect(abs(final.width - initial.width - widthChange) < 1)
            // A lazy stack can refine its estimated height in several passes. What
            // must not happen is another text reflow for every animation frame.
            #expect(model.samples.allSatisfy {
                abs($0.width - initial.width) < 1 || abs($0.width - final.width) < 1
            })
            #expect(abs(final.bottomGap) < 1)
            // The sidebar keeps the transition animation. Geometry callbacks on
            // its fixed-width content report its destination, not each slide frame.
            #expect(model.sidebarAnimationTransactions.contains(true))
            #expect(abs((model.sidebarEdges.last ?? -1) - (visible ? model.sidebarWidth : 0)) < 1)
            #expect(model.detailAppearances == 1)
        }
    }

    @Test("Opening the sidebar does not take a history reader to the bottom")
    func preservesHistoryReading() async throws {
        let model = Model()
        let window = makeWindow(model: model, width: 1_000)
        defer { window.close() }
        try await settle()
        model.historyTarget = 45
        try await settle()
        let initial = try #require(model.samples.last)
        try #require(initial.bottomGap > 1_000)
        model.samples.removeAll()

        withAnimation(.smooth(duration: 0.25)) {
            model.isSidebarVisible = true
        }
        try await settle()
        let final = try #require(model.samples.last)
        #expect(final.bottomGap > 1_000)
        #expect(model.samples.allSatisfy { abs($0.width - final.width) < 1 })
        #expect(model.detailAppearances == 1)
    }

    @Test("A rapid reversal settles without rebuilding the transcript")
    func handlesInterruptedToggle() async throws {
        let model = Model()
        let window = makeWindow(model: model, width: 1_000)
        defer { window.close() }
        try await settle()
        let initial = try #require(model.samples.last)
        model.samples.removeAll()

        withAnimation(.smooth(duration: 0.25)) { model.isSidebarVisible = true }
        try await Task.sleep(for: .milliseconds(60))
        withAnimation(.smooth(duration: 0.25)) { model.isSidebarVisible = false }
        try await settle()

        let final = try #require(model.samples.last)
        #expect(abs(final.width - initial.width) < 1)
        #expect(abs(final.bottomGap) < 1)
        #expect(model.samples.allSatisfy {
            abs($0.width - initial.width) < 1
                || abs($0.width - (initial.width - model.sidebarWidth)) < 1
        })
        #expect(model.detailAppearances == 1)
    }

    @Test("Animations originating in the detail remain enabled")
    func preservesDetailAnimations() async throws {
        let model = Model()
        let window = makeWindow(model: model, width: 1_000)
        defer { window.close() }
        try await settle()
        withAnimation(.smooth(duration: 0.25)) { model.isSidebarVisible = true }
        try await settle()
        model.detailAnimationTransactions.removeAll()

        withAnimation(.easeInOut(duration: 0.2)) { model.detailRevision += 1 }
        try await settle()
        #expect(model.detailAnimationTransactions.contains(true))
    }

    private func settle() async throws {
        // Wait through the smooth animation's spring tail as well as lazy measurement.
        try await Task.sleep(for: .milliseconds(850))
    }

    private func makeWindow(model: Model, width: Double) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: Fixture(model: model)))
        window.setContentSize(NSSize(width: width, height: 700))
        // Exercise real SwiftUI layout without showing UI or launching the app.
        window.alphaValue = 0
        window.orderFront(nil)
        return window
    }

    @Observable
    final class Model {
        var isSidebarVisible = false
        var sidebarWidth = AppDesign.sidebarIdealWidth
        var historyTarget: Int?
        var detailRevision = 0
        @ObservationIgnored var samples: [Sample] = []
        @ObservationIgnored var sidebarEdges: [Double] = []
        @ObservationIgnored var detailAppearances = 0
        @ObservationIgnored var sidebarAnimationTransactions: [Bool] = []
        @ObservationIgnored var detailAnimationTransactions: [Bool] = []
    }

    struct Sample: Equatable {
        let width: Double
        let bottomGap: Double
    }

    private struct Fixture: View {
        @Bindable var model: Model

        var body: some View {
            MacSidebarSplitView(
                isSidebarVisible: model.isSidebarVisible,
                sidebarWidth: $model.sidebarWidth,
                collapseSidebar: { model.isSidebarVisible = false }
            ) {
                TransactionProbe(revision: model.isSidebarVisible ? 1 : 0, isSidebar: true, model: model)
                    .onGeometryChange(for: Double.self) { $0.frame(in: .global).maxX } action: {
                        model.sidebarEdges.append($0)
                    }
            } detail: {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                                ForEach(0..<100) { index in
                                    VStack(alignment: .leading) {
                                        Text("Message \(index)").bold()
                                        Text(String(repeating: "聊天内容重新换行时应保持阅读位置。This is a wrapping transcript row. ", count: 3 + index % 8))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                                }
                                Color.clear.frame(height: 1)
                            }
                            .padding(.top, AppDesign.contentPadding)
                            .padding(.bottom, AppDesign.compactSpacing)
                            .frame(maxWidth: AppDesign.chatContentMaximumWidth)
                            .frame(maxWidth: .infinity)
                        }
                        .contentMargins(.horizontal, AppDesign.contentPadding, for: .scrollContent)
                        .defaultScrollAnchor(.bottom, for: .initialOffset)
                        .onScrollGeometryChange(for: Sample.self) { geometry in
                            Sample(
                                width: geometry.containerSize.width,
                                bottomGap: geometry.contentSize.height - geometry.visibleRect.maxY
                            )
                        } action: { _, sample in model.samples.append(sample) }
                        .onChange(of: model.historyTarget) { _, target in
                            if let target { proxy.scrollTo(target, anchor: .top) }
                        }
                    }
                    Color.clear.frame(height: 100)
                    TransactionProbe(revision: model.detailRevision, isSidebar: false, model: model)
                        .frame(width: 0, height: 0)
                }
                .onAppear { model.detailAppearances += 1 }
            }
        }
    }

    private struct TransactionProbe: NSViewRepresentable {
        let revision: Int
        let isSidebar: Bool
        let model: Model

        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ nsView: NSView, context: Context) {
            if isSidebar {
                model.sidebarAnimationTransactions.append(context.transaction.animation != nil)
            } else {
                model.detailAnimationTransactions.append(context.transaction.animation != nil)
            }
        }
    }
}
#endif
