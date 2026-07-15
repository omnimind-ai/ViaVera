import Foundation
import WebKit

@MainActor
struct AppleBrowserPresentationSnapshot {
    struct TabSummary: Identifiable, Equatable {
        let id: Int
        let title: String
        let url: String
        let isActive: Bool
    }

    static let empty = AppleBrowserPresentationSnapshot(
        activeTab: nil,
        activeTabID: nil,
        title: "",
        url: "",
        isLoading: false,
        canGoBack: false,
        canGoForward: false,
        riskChallengeDetected: false,
        tabs: []
    )

    let activeTab: AppleBrowserTab?
    let activeTabID: Int?
    let title: String
    let url: String
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let riskChallengeDetected: Bool
    let tabs: [TabSummary]
}

nonisolated struct AppleBrowserPreviewFrame: Sendable {
    let data: Data
    let title: String
    let url: String
    let isLoading: Bool
}

extension AppleBrowserSession {
    func prepareForPresentation(
        conversationID: UUID
    ) throws -> AppleBrowserTab {
        bind(to: conversationID)
        if let activeTabID, let tab = tabs[activeTabID] {
            return tab
        }
        return try createTab()
    }

    func presentationSnapshot(
        for conversationID: UUID
    ) -> AppleBrowserPresentationSnapshot {
        guard boundConversationID == conversationID else { return .empty }
        let activeTab = activeTabID.flatMap { tabs[$0] }
        let summaries = tabs.values
            .sorted { $0.id < $1.id }
            .map { tab in
                AppleBrowserPresentationSnapshot.TabSummary(
                    id: tab.id,
                    title: pageTitle(for: tab),
                    url: pageURL(for: tab),
                    isActive: tab.id == activeTabID
                )
            }
        return AppleBrowserPresentationSnapshot(
            activeTab: activeTab,
            activeTabID: activeTab?.id,
            title: activeTab.map { pageTitle(for: $0) } ?? "",
            url: activeTab.map { pageURL(for: $0) } ?? "",
            isLoading: activeTab?.page.isLoading ?? false,
            canGoBack: activeTab?.page.backForwardList.backList.isEmpty == false,
            canGoForward: activeTab?.page.backForwardList.forwardList.isEmpty == false,
            riskChallengeDetected: activeTab?.lastRiskReport.detected ?? false,
            tabs: summaries
        )
    }

    func navigateFromPresentation(
        to rawURL: String,
        conversationID: UUID
    ) async throws {
        let tab = try prepareForPresentation(conversationID: conversationID)
        _ = try await load(
            rawURL: rawURL,
            in: tab,
            timeoutMilliseconds: 30_000
        )
        tab.lastRiskReport = await assessRisk(on: tab)
    }

    func goBackFromPresentation(conversationID: UUID) async throws {
        let tab = try prepareForPresentation(conversationID: conversationID)
        guard let item = tab.page.backForwardList.backList.last else {
            throw AppleBrowserError.noBackHistory
        }
        activeTabID = tab.id
        try await awaitNavigation(
            to: item,
            in: tab,
            timeoutMilliseconds: 30_000,
            action: "manual_go_back"
        )
        tab.lastRiskReport = await assessRisk(on: tab)
    }

    func goForwardFromPresentation(conversationID: UUID) async throws {
        let tab = try prepareForPresentation(conversationID: conversationID)
        guard let item = tab.page.backForwardList.forwardList.first else {
            throw AppleBrowserError.noForwardHistory
        }
        activeTabID = tab.id
        try await awaitNavigation(
            to: item,
            in: tab,
            timeoutMilliseconds: 30_000,
            action: "manual_go_forward"
        )
        tab.lastRiskReport = await assessRisk(on: tab)
    }

    func reloadFromPresentation(conversationID: UUID) async throws {
        let tab = try prepareForPresentation(conversationID: conversationID)
        activeTabID = tab.id
        try await awaitReload(in: tab, timeoutMilliseconds: 30_000)
        tab.lastRiskReport = await assessRisk(on: tab)
    }

    func stopLoadingFromPresentation(conversationID: UUID) {
        guard boundConversationID == conversationID,
              let activeTabID,
              let tab = tabs[activeTabID] else {
            return
        }
        tab.page.stopLoading()
    }

    func refreshRiskFromPresentation(conversationID: UUID) async {
        guard boundConversationID == conversationID,
              let activeTabID,
              let tab = tabs[activeTabID] else {
            return
        }
        tab.lastRiskReport = await assessRisk(on: tab)
    }

    @discardableResult
    func createTabFromPresentation(
        conversationID: UUID
    ) throws -> AppleBrowserTab {
        bind(to: conversationID)
        return try createTab()
    }

    func selectTabFromPresentation(
        _ tabID: Int,
        conversationID: UUID
    ) throws {
        bind(to: conversationID)
        guard tabs[tabID] != nil else {
            throw AppleBrowserError.missingTab(tabID)
        }
        activeTabID = tabID
    }

    func closeActiveTabFromPresentation(conversationID: UUID) {
        guard boundConversationID == conversationID,
              let activeTabID,
              let tab = tabs[activeTabID] else {
            return
        }
        tab.page.stopLoading()
        tabs[activeTabID] = nil
        self.activeTabID = tabs.keys.max()
    }

    func capturePreviewFrame(
        for conversationID: UUID,
        maximumWidth: Int = 420
    ) async throws -> AppleBrowserPreviewFrame? {
        guard boundConversationID == conversationID,
              let activeTabID,
              let tab = tabs[activeTabID] else {
            return nil
        }
        let viewport = try await callJavaScript(
            in: tab,
            functionBody: "return {x: window.scrollX, y: window.scrollY, width: window.innerWidth, height: window.innerHeight};"
        )
        let screenshotRect = boundedScreenshotRect(from: viewport)
        let snapshotWidth = min(
            screenshotRect.width,
            CGFloat(max(80, min(maximumWidth, 800)))
        )
        let data = try await tab.page.exported(
            as: .image(
                region: .rect(screenshotRect),
                snapshotWidth: snapshotWidth
            )
        )
        guard data.count <= 8 * 1_024 * 1_024 else {
            throw OmniAgentToolError("The browser preview frame exceeded 8 MiB.")
        }
        return AppleBrowserPreviewFrame(
            data: data,
            title: pageTitle(for: tab),
            url: pageURL(for: tab),
            isLoading: tab.page.isLoading
        )
    }

    private func awaitReload(
        in tab: AppleBrowserTab,
        timeoutMilliseconds: Int
    ) async throws {
        let page = tab.page
        let timeoutState = AppleBrowserNavigationTimeoutState()
        let timeoutTask = Task { @MainActor [page, timeoutState] in
            try await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            timeoutState.didFire = true
            page.stopLoading()
        }
        defer { timeoutTask.cancel() }

        do {
            for try await event in page.reload() {
                if event == .finished {
                    break
                }
            }
        } catch {
            page.stopLoading()
            if timeoutState.didFire {
                throw AppleBrowserError.timedOut(
                    action: "manual_reload",
                    milliseconds: timeoutMilliseconds
                )
            }
            throw error
        }
        if timeoutState.didFire {
            throw AppleBrowserError.timedOut(
                action: "manual_reload",
                milliseconds: timeoutMilliseconds
            )
        }
    }
}
