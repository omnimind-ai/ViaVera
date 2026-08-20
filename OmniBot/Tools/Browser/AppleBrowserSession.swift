import Foundation
import WebKit

nonisolated enum AppleBrowserWebsiteDataStorePolicy: String, Sendable {
    /// Cookies, caches, and other website data live only for the currently
    /// bound conversation and are discarded when the conversation changes.
    case nonPersistentPerConversation = "non_persistent_per_conversation"
}

nonisolated struct AppleBrowserCookieFilterResult: Equatable, Sendable {
    let matchingIndices: [Int]
    let keywords: [String]
    let totalMatched: Int
    let truncated: Bool
}

@MainActor
final class AppleBrowserSession {
    static let maximumSimultaneousTabs = 3
    nonisolated static let maximumReturnedCookieMetadata = 200

    let paths: WorkspacePaths
    let workspaceFileSystem: WorkspaceDescriptorFileSystem
    let websiteDataStorePolicy: AppleBrowserWebsiteDataStorePolicy

    private(set) var websiteDataStore: WKWebsiteDataStore
    private(set) var boundConversationID: UUID?

    var tabs: [Int: AppleBrowserTab] = [:]
    var activeTabID: Int?
    var nextTabID = 1

    private let makeWebsiteDataStore: () -> WKWebsiteDataStore

    init(
        paths: WorkspacePaths,
        fileManager: FileManager = .default,
        websiteDataStorePolicy: AppleBrowserWebsiteDataStorePolicy = .nonPersistentPerConversation,
        makeWebsiteDataStore: @escaping () -> WKWebsiteDataStore = {
            WKWebsiteDataStore.nonPersistent()
        }
    ) {
        self.paths = paths
        _ = fileManager
        self.workspaceFileSystem = WorkspaceDescriptorFileSystem(paths: paths)
        self.websiteDataStorePolicy = websiteDataStorePolicy
        self.makeWebsiteDataStore = makeWebsiteDataStore
        self.websiteDataStore = makeWebsiteDataStore()
    }

    func execute(
        action: AppleBrowserAction,
        arguments: OmniToolArguments,
        context: AgentToolExecutionContext,
        resourceProtocol: AgentResourceProtocol
    ) async throws -> AgentToolExecutionResult {
        bind(to: context.conversationID)

        switch action {
        case .newTab:
            return try await executeNewTab(arguments)
        case .closeTab:
            return try executeCloseTab(arguments)
        case .listTabs:
            return try executeListTabs()
        default:
            break
        }

        let tab = try selectedTab(
            arguments,
            createIfMissing: action == .navigate
        )
        if action.isAutomatedInteraction, tab.lastRiskReport.detected {
            return blockedByRiskChallenge(tab: tab, action: action)
        }

        let output: AppleBrowserOperationOutput
        switch action {
        case .navigate:
            output = try await navigate(arguments, in: tab)
        case .screenshot:
            output = try await captureScreenshot(
                arguments,
                tab: tab,
                context: context,
                resourceProtocol: resourceProtocol
            )
        case .click:
            output = try await click(arguments, in: tab)
        case .type:
            output = try await type(arguments, in: tab)
        case .getText:
            output = try await getText(arguments, in: tab)
        case .scroll:
            output = try await scroll(arguments, in: tab)
        case .getPageInfo:
            output = try await getPageInfo(in: tab)
        case .executeJavaScript:
            output = try await executeJavaScript(arguments, in: tab)
        case .findElements:
            output = try await findElements(arguments, in: tab)
        case .hover:
            output = try await hover(arguments, in: tab)
        case .getReadable:
            output = try await getReadable(in: tab)
        case .setUserAgent:
            output = try setUserAgent(arguments, in: tab)
        case .getBackbone:
            output = try await getBackbone(arguments, in: tab)
        case .fetch:
            output = try await fetch(
                arguments,
                in: tab,
                context: context,
                resourceProtocol: resourceProtocol
            )
        case .getCookies:
            output = try await getCookies(arguments, for: tab)
        case .scrollAndCollect:
            output = try await scrollAndCollect(arguments, in: tab)
        case .goBack:
            output = try await goBack(arguments, in: tab)
        case .goForward:
            output = try await goForward(arguments, in: tab)
        case .pressKey:
            output = try await pressKey(arguments, in: tab)
        case .waitForSelector:
            output = try await waitForSelector(arguments, in: tab)
        case .newTab, .closeTab, .listTabs:
            preconditionFailure("Tab lifecycle actions are handled before selecting a tab.")
        }

        let riskReport = await assessRisk(on: tab)
        return try makeResult(
            output,
            tab: tab,
            riskReport: riskReport
        )
    }

    /// A browser session belongs to exactly one conversation at a time. When
    /// ownership changes, no tab or website data from the previous
    /// conversation remains addressable by the next one.
    func bind(to conversationID: UUID) {
        guard boundConversationID != conversationID else { return }

        if boundConversationID != nil {
            for tab in tabs.values {
                tab.page.stopLoading()
            }
            tabs.removeAll(keepingCapacity: false)
            activeTabID = nil
            nextTabID = 1

            switch websiteDataStorePolicy {
            case .nonPersistentPerConversation:
                websiteDataStore = makeWebsiteDataStore()
            }
        }

        boundConversationID = conversationID
    }

    func makePage() -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = websiteDataStore
        configuration.upgradeKnownHostsToHTTPS = true
        var navigationPreferences = configuration.defaultNavigationPreferences
        navigationPreferences.allowsContentJavaScript = true
        navigationPreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
        configuration.defaultNavigationPreferences = navigationPreferences
        let page = WebPage(configuration: configuration)
        page.customUserAgent = AppleBrowserUserAgent.currentDefault
        return page
    }

    func createTab() throws -> AppleBrowserTab {
        guard tabs.count < Self.maximumSimultaneousTabs else {
            throw AppleBrowserError.maximumTabsReached(Self.maximumSimultaneousTabs)
        }
        guard nextTabID < Int.max else {
            throw OmniAgentToolError("The browser tab identifier space is exhausted.")
        }
        let id = nextTabID
        nextTabID += 1
        let tab = AppleBrowserTab(id: id, page: makePage())
        tabs[id] = tab
        activeTabID = id
        return tab
    }

    func selectedTab(
        _ arguments: OmniToolArguments,
        createIfMissing: Bool
    ) throws -> AppleBrowserTab {
        if let requestedID = try arguments.integer("tab_id", range: 1 ... Int.max) {
            guard let tab = tabs[requestedID] else {
                throw AppleBrowserError.missingTab(requestedID)
            }
            activeTabID = requestedID
            return tab
        }
        if let activeTabID, let tab = tabs[activeTabID] {
            return tab
        }
        if createIfMissing {
            return try createTab()
        }
        throw AppleBrowserError.noActiveTab
    }

    func executeNewTab(
        _ arguments: OmniToolArguments
    ) async throws -> AgentToolExecutionResult {
        let tab = try createTab()
        var navigationOutput: AppleBrowserOperationOutput?
        if let rawURL = try arguments.optionalString("url", maximumLength: 4_096),
           !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let timeout = try navigationTimeout(arguments)
            navigationOutput = try await load(
                rawURL: rawURL,
                in: tab,
                timeoutMilliseconds: timeout
            )
        }
        let riskReport = await assessRisk(on: tab)
        let payload = AgentValue.object([
            "tabId": .number(Double(tab.id)),
            "url": .string(pageURL(for: tab)),
            "title": .string(pageTitle(for: tab)),
        ])
        let output = AppleBrowserOperationOutput(
            summary: navigationOutput == nil
                ? "Created browser tab \(tab.id)."
                : "Created browser tab \(tab.id) and navigated it.",
            payload: payload
        )
        return try makeResult(output, tab: tab, riskReport: riskReport)
    }

    func executeCloseTab(
        _ arguments: OmniToolArguments
    ) throws -> AgentToolExecutionResult {
        let tab = try selectedTab(arguments, createIfMissing: false)
        tab.page.stopLoading()
        tabs[tab.id] = nil
        if activeTabID == tab.id {
            activeTabID = tabs.keys.max()
        }
        let payload = AgentValue.object([
            "closedTabId": .number(Double(tab.id)),
            "activeTabId": activeTabID.map { .number(Double($0)) } ?? .null,
            "remainingTabCount": .number(Double(tabs.count)),
        ])
        return try makeResultWithoutTab(
            AppleBrowserOperationOutput(
                summary: "Closed browser tab \(tab.id).",
                payload: payload
            )
        )
    }

    func executeListTabs() throws -> AgentToolExecutionResult {
        let values = tabs.values
            .sorted { $0.id < $1.id }
            .map { tab in
                AgentValue.object([
                    "tabId": .number(Double(tab.id)),
                    "active": .bool(tab.id == activeTabID),
                    "url": .string(pageURL(for: tab)),
                    "title": .string(pageTitle(for: tab)),
                    "isLoading": .bool(tab.page.isLoading),
                    "riskChallengeDetected": .bool(tab.lastRiskReport.detected),
                ])
            }
        let output = AppleBrowserOperationOutput(
            summary: "Listed \(values.count) browser tab(s).",
            payload: .array(values)
        )
        return try makeResultWithoutTab(output)
    }

    func navigate(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let rawURL = try arguments.requiredString("url", maximumLength: 4_096)
        return try await load(
            rawURL: rawURL,
            in: tab,
            timeoutMilliseconds: navigationTimeout(arguments)
        )
    }

    func load(
        rawURL: String,
        in tab: AppleBrowserTab,
        timeoutMilliseconds: Int
    ) async throws -> AppleBrowserOperationOutput {
        let url = try normalizedWebURL(rawURL)
        activeTabID = tab.id
        try await awaitNavigation(
            to: url,
            in: tab,
            timeoutMilliseconds: timeoutMilliseconds,
            action: "navigate"
        )
        return AppleBrowserOperationOutput(
            summary: "Navigated browser tab \(tab.id).",
            payload: .object([
                "requestedUrl": .string(url.absoluteString),
                "finalUrl": .string(pageURL(for: tab, fallback: url.absoluteString)),
                "title": .string(pageTitle(for: tab)),
                "secureContentOnly": .bool(tab.page.hasOnlySecureContent),
            ]),
            metadata: [
                "requestedScheme": .string(url.scheme?.lowercased() ?? ""),
            ]
        )
    }

    func normalizedWebURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppleBrowserError.invalidURL(rawValue)
        }
        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              url.host != nil else {
            throw AppleBrowserError.invalidURL(rawValue)
        }
        guard scheme == "https" || scheme == "http" else {
            throw AppleBrowserError.unsupportedURLScheme(scheme)
        }
        return url
    }

    func goBack(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        guard let item = tab.page.backForwardList.backList.last else {
            throw AppleBrowserError.noBackHistory
        }
        try await awaitNavigation(
            to: item,
            in: tab,
            timeoutMilliseconds: navigationTimeout(arguments),
            action: "go_back"
        )
        return AppleBrowserOperationOutput(
            summary: "Navigated browser tab \(tab.id) backward.",
            payload: .object([
                "url": .string(pageURL(for: tab, fallback: item.url.absoluteString)),
                "title": .string(pageTitle(for: tab)),
            ])
        )
    }

    func goForward(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        guard let item = tab.page.backForwardList.forwardList.first else {
            throw AppleBrowserError.noForwardHistory
        }
        try await awaitNavigation(
            to: item,
            in: tab,
            timeoutMilliseconds: navigationTimeout(arguments),
            action: "go_forward"
        )
        return AppleBrowserOperationOutput(
            summary: "Navigated browser tab \(tab.id) forward.",
            payload: .object([
                "url": .string(pageURL(for: tab, fallback: item.url.absoluteString)),
                "title": .string(pageTitle(for: tab)),
            ])
        )
    }

    func setUserAgent(
        _ arguments: OmniToolArguments,
        in tab: AppleBrowserTab
    ) throws -> AppleBrowserOperationOutput {
        let rawProfile = try arguments.requiredString("user_agent", maximumLength: 64)
        guard let profile = AppleBrowserUserAgentProfile(rawValue: rawProfile) else {
            throw OmniAgentToolError(
                "Invalid parameter 'user_agent': expected desktop_safari or mobile_safari."
            )
        }
        let userAgent = AppleBrowserUserAgent.current(profile: profile)
        tab.page.customUserAgent = userAgent
        return AppleBrowserOperationOutput(
            summary: "Set the WebKit user-agent profile for browser tab \(tab.id).",
            payload: .object([
                "profile": .string(profile.rawValue),
                "appliesOnNextNavigation": .bool(true),
            ])
        )
    }

    func getCookies(
        _ arguments: OmniToolArguments,
        for tab: AppleBrowserTab
    ) async throws -> AppleBrowserOperationOutput {
        let currentHost = tab.page.url?.host?.lowercased()
        let cookies = await websiteDataStore.httpCookieStore.allCookies()
            .filter { cookie in
                guard let currentHost else { return false }
                let domain = cookie.domain
                    .trimmingPrefix(".")
                    .lowercased()
                return currentHost == domain || currentHost.hasSuffix(".\(domain)")
            }
            .sorted { lhs, rhs in
                if lhs.domain == rhs.domain { return lhs.name < rhs.name }
                return lhs.domain < rhs.domain
            }
        let fuzzy = try arguments.bool("fuzzy", default: true)
        let filter = Self.filterCookieNames(
            cookies.map(\.name),
            keywords: try arguments.optionalString("keywords", maximumLength: 4_096),
            fuzzy: fuzzy,
            limit: Self.maximumReturnedCookieMetadata
        )
        let exportedCookies = filter.matchingIndices.map { cookies[$0] }
        let values = exportedCookies.map { cookie in
            AgentValue.object([
                "name": .string(cookie.name),
                "domain": .string(cookie.domain),
                "path": .string(cookie.path),
                "secure": .bool(cookie.isSecure),
                "httpOnly": .bool(cookie.isHTTPOnly),
                "sessionOnly": .bool(cookie.isSessionOnly),
                "expiresAt": cookie.expiresDate.map {
                    .string($0.ISO8601Format())
                } ?? .null,
                "valueRedacted": .bool(true),
            ])
        }
        return AppleBrowserOperationOutput(
            summary: "Listed cookie metadata for the active origin. Cookie values were not returned.",
            payload: .object([
                "cookies": .array(values),
                "keywords": .array(filter.keywords.map(AgentValue.string)),
                "fuzzy": .bool(fuzzy),
                "returnedCount": .number(Double(values.count)),
                "totalMatched": .number(Double(filter.totalMatched)),
                "truncated": .bool(filter.truncated),
            ]),
            metadata: [
                "cookieValuesReturned": .bool(false),
                "returnedCount": .number(Double(values.count)),
                "totalMatched": .number(Double(filter.totalMatched)),
                "truncated": .bool(filter.truncated),
            ]
        )
    }

    nonisolated static func filterCookieNames(
        _ names: [String],
        keywords rawKeywords: String?,
        fuzzy: Bool,
        limit: Int = maximumReturnedCookieMetadata
    ) -> AppleBrowserCookieFilterResult {
        let keywords = (rawKeywords ?? "")
            .split(whereSeparator: \Character.isWhitespace)
            .map { $0.lowercased() }
        let matchedIndices = names.indices.filter { index in
            guard !keywords.isEmpty else { return true }
            let name = names[index].lowercased()
            if fuzzy {
                return keywords.allSatisfy(name.contains)
            }
            return keywords.contains(name)
        }
        let boundedLimit = max(0, limit)
        return AppleBrowserCookieFilterResult(
            matchingIndices: Array(matchedIndices.prefix(boundedLimit)),
            keywords: keywords,
            totalMatched: matchedIndices.count,
            truncated: matchedIndices.count > boundedLimit
        )
    }

    func captureScreenshot(
        _ arguments: OmniToolArguments,
        tab: AppleBrowserTab,
        context: AgentToolExecutionContext,
        resourceProtocol: AgentResourceProtocol
    ) async throws -> AppleBrowserOperationOutput {
        _ = try arguments.bool("read_image", default: false)
        let viewport = try await callJavaScript(
            in: tab,
            functionBody: "return {x: window.scrollX, y: window.scrollY, width: window.innerWidth, height: window.innerHeight};"
        )
        let screenshotRect = boundedScreenshotRect(from: viewport)
        let data = try await tab.page.exported(
            as: .image(
                region: .rect(screenshotRect),
                snapshotWidth: screenshotRect.width
            )
        )
        guard data.count <= 24 * 1_024 * 1_024 else {
            throw OmniAgentToolError("The browser screenshot exceeded the 24 MiB artifact limit.")
        }
        let artifact = try persistBrowserArtifact(
            data,
            preferredName: "tab-\(tab.id)-\(UUID().uuidString).\(imageFileExtension(for: data))",
            title: pageTitle(for: tab).isEmpty
                ? "Browser screenshot"
                : "Browser screenshot — \(pageTitle(for: tab))",
            context: context,
            resourceProtocol: resourceProtocol,
            maximumBytes: 24 * 1_024 * 1_024
        )
        return AppleBrowserOperationOutput(
            summary: "Captured a WebKit screenshot as a workspace artifact. The image was not read by the model or injected into a VLM.",
            payload: .object([
                "artifactUri": .string(artifact.uri),
                "renderMarkdown": .string(artifact.renderMarkdown),
                "readImageSupported": .bool(false),
                "vlmInjected": .bool(false),
            ]),
            metadata: [
                "readImageSupported": .bool(false),
                "vlmInjected": .bool(false),
                "captureRegion": .object([
                    "x": .number(screenshotRect.origin.x),
                    "y": .number(screenshotRect.origin.y),
                    "width": .number(screenshotRect.width),
                    "height": .number(screenshotRect.height),
                ]),
            ],
            artifacts: [artifact]
        )
    }

    func makeResult(
        _ output: AppleBrowserOperationOutput,
        tab: AppleBrowserTab,
        riskReport: AppleBrowserRiskReport
    ) throws -> AgentToolExecutionResult {
        var metadata = output.metadata
        metadata.merge(browserMetadata(tab: tab, riskReport: riskReport)) { current, _ in current }
        return AgentToolExecutionResult(
            content: try content(summary: output.summary, payload: output.payload),
            metadata: metadata,
            artifacts: output.artifacts,
            workspaceID: output.artifacts.isEmpty ? nil : "shared"
        )
    }

    func makeResultWithoutTab(
        _ output: AppleBrowserOperationOutput
    ) throws -> AgentToolExecutionResult {
        var metadata = output.metadata
        metadata["engine"] = .string("WebKit.WebPage")
        metadata["safariAppControlled"] = .bool(false)
        metadata["sharesSafariCookies"] = .bool(false)
        metadata["websiteDataStorePolicy"] = .string(websiteDataStorePolicy.rawValue)
        metadata["manualTakeoverSupported"] = .bool(true)
        metadata["httpsPreferred"] = .bool(true)
        return AgentToolExecutionResult(
            content: try content(summary: output.summary, payload: output.payload),
            metadata: metadata,
            artifacts: output.artifacts,
            workspaceID: output.artifacts.isEmpty ? nil : "shared"
        )
    }

    func blockedByRiskChallenge(
        tab: AppleBrowserTab,
        action: AppleBrowserAction
    ) -> AgentToolExecutionResult {
        AgentToolExecutionResult(
            content: "Automated browser action '\(action.rawValue)' stopped because the page appears to be a CAPTCHA, anti-bot, or unusual-traffic challenge. Open the chat browser card and complete the challenge manually in this same WebKit session before continuing automation.",
            isError: true,
            metadata: browserMetadata(tab: tab, riskReport: tab.lastRiskReport)
                .merging([
                    "blockedAction": .string(action.rawValue),
                    "automationStopped": .bool(true),
                ]) { current, _ in current }
        )
    }

    func browserMetadata(
        tab: AppleBrowserTab,
        riskReport: AppleBrowserRiskReport
    ) -> [String: AgentValue] {
        [
            "engine": .string("WebKit.WebPage"),
            "safariAppControlled": .bool(false),
            "sharesSafariCookies": .bool(false),
            "websiteDataStorePolicy": .string(websiteDataStorePolicy.rawValue),
            "manualTakeoverSupported": .bool(true),
            "httpsPreferred": .bool(true),
            "tabId": .number(Double(tab.id)),
            "url": .string(pageURL(for: tab)),
            "title": .string(pageTitle(for: tab)),
            "riskChallengeDetected": .bool(riskReport.detected),
            "riskSignals": .array(riskReport.signals.map(AgentValue.string)),
        ]
    }

    func content(summary: String, payload: AgentValue) throws -> String {
        guard payload != .null else { return summary }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard data.count <= 128 * 1_024 else {
            throw AppleBrowserError.javaScriptResultTooLarge
        }
        return "\(summary)\n\(String(decoding: data, as: UTF8.self))"
    }

    func pageTitle(for tab: AppleBrowserTab) -> String {
        String(tab.page.title.prefix(500))
    }

    func pageURL(
        for tab: AppleBrowserTab,
        fallback: String = "about:blank"
    ) -> String {
        String((tab.page.url?.absoluteString ?? fallback).prefix(4_096))
    }

    func boundedScreenshotRect(from value: AgentValue) -> CGRect {
        guard case let .object(object) = value else {
            return CGRect(x: 0, y: 0, width: 1_280, height: 900)
        }
        func number(_ key: String, default defaultValue: Double) -> Double {
            guard case let .number(value) = object[key], value.isFinite else {
                return defaultValue
            }
            return value
        }
        let x = max(0, number("x", default: 0))
        let y = max(0, number("y", default: 0))
        let width = min(1_920, max(320, number("width", default: 1_280)))
        let height = min(1_080, max(320, number("height", default: 900)))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func imageFileExtension(for data: Data) -> String {
        let signature = Array(data.prefix(4))
        if signature.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if signature.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if signature.starts(with: [0x49, 0x49, 0x2A, 0x00])
            || signature.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "tiff"
        }
        return "png"
    }

    func persistBrowserArtifact(
        _ data: Data,
        preferredName: String,
        title: String,
        context: AgentToolExecutionContext,
        resourceProtocol: AgentResourceProtocol,
        maximumBytes: Int
    ) throws -> AgentArtifact {
        let runDirectory = try workspaceFileSystem.parse(
            ".omnibot/browser/\(context.runID.uuidString)"
        )
        let relativeFile = try workspaceFileSystem.atomicallyWriteUnique(
            data,
            in: runDirectory,
            preferredName: preferredName,
            maximumBytes: maximumBytes
        )
        let fileURL = relativeFile.components.reduce(paths.root) { partial, component in
            partial.appending(path: component)
        }
        return try resourceProtocol.artifact(
            for: fileURL,
            sourceTool: "browser_use",
            title: title
        )
    }

    func navigationTimeout(_ arguments: OmniToolArguments) throws -> Int {
        try arguments.integer(
            "timeout_ms",
            default: 15_000,
            range: 500 ... 30_000
        ) ?? 15_000
    }

    func awaitNavigation(
        to url: URL,
        in tab: AppleBrowserTab,
        timeoutMilliseconds: Int,
        action: String
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
            for try await event in page.load(url) {
                if event == .finished {
                    break
                }
            }
        } catch {
            page.stopLoading()
            if timeoutState.didFire {
                throw AppleBrowserError.timedOut(
                    action: action,
                    milliseconds: timeoutMilliseconds
                )
            }
            throw error
        }
        if timeoutState.didFire {
            throw AppleBrowserError.timedOut(
                action: action,
                milliseconds: timeoutMilliseconds
            )
        }
    }

    func awaitNavigation(
        to item: WebPage.BackForwardList.Item,
        in tab: AppleBrowserTab,
        timeoutMilliseconds: Int,
        action: String
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
            for try await event in page.load(item) {
                if event == .finished {
                    break
                }
            }
        } catch {
            page.stopLoading()
            if timeoutState.didFire {
                throw AppleBrowserError.timedOut(
                    action: action,
                    milliseconds: timeoutMilliseconds
                )
            }
            throw error
        }
        if timeoutState.didFire {
            throw AppleBrowserError.timedOut(
                action: action,
                milliseconds: timeoutMilliseconds
            )
        }
    }
}
