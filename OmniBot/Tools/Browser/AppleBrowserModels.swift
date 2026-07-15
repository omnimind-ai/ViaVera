import Foundation
import WebKit

nonisolated struct AppleBrowserRiskReport: Sendable {
    static let clear = AppleBrowserRiskReport(detected: false, signals: [])

    let detected: Bool
    let signals: [String]
}

nonisolated struct AppleBrowserOperationOutput: Sendable {
    let summary: String
    let payload: AgentValue
    let metadata: [String: AgentValue]
    let artifacts: [AgentArtifact]

    init(
        summary: String,
        payload: AgentValue = .null,
        metadata: [String: AgentValue] = [:],
        artifacts: [AgentArtifact] = []
    ) {
        self.summary = summary
        self.payload = payload
        self.metadata = metadata
        self.artifacts = artifacts
    }
}

@MainActor
final class AppleBrowserTab {
    let id: Int
    let page: WebPage
    var lastRiskReport = AppleBrowserRiskReport.clear

    init(id: Int, page: WebPage) {
        self.id = id
        self.page = page
    }
}

@MainActor
final class AppleBrowserNavigationTimeoutState {
    var didFire = false
}

nonisolated enum AppleBrowserError: LocalizedError, Sendable {
    case invalidAction(String)
    case invalidURL(String)
    case unsupportedURLScheme(String)
    case noActiveTab
    case missingTab(Int)
    case maximumTabsReached(Int)
    case missingSelectorOrCoordinates
    case noBackHistory
    case noForwardHistory
    case timedOut(action: String, milliseconds: Int)
    case javaScriptResultTooLarge
    case invalidFetchResponse
    case fetchBodyTooLarge(actualBytes: Int64?, maximumBytes: Int)
    case invalidFetchBodyEncoding

    var errorDescription: String? {
        switch self {
        case let .invalidAction(action):
            "Unsupported browser action: \(action)."
        case let .invalidURL(value):
            "Invalid browser URL: \(value)."
        case let .unsupportedURLScheme(scheme):
            "Unsupported browser URL scheme: \(scheme). Only HTTP and HTTPS are allowed."
        case .noActiveTab:
            "The browser has no active tab. Navigate or create a tab first."
        case let .missingTab(id):
            "Browser tab \(id) does not exist."
        case let .maximumTabsReached(limit):
            "The browser allows at most \(limit) simultaneous tabs. Close a tab before opening another."
        case .missingSelectorOrCoordinates:
            "Provide a selector or both coordinate_x and coordinate_y."
        case .noBackHistory:
            "The active browser tab has no back history."
        case .noForwardHistory:
            "The active browser tab has no forward history."
        case let .timedOut(action, milliseconds):
            "Browser action '\(action)' timed out after \(milliseconds) milliseconds."
        case .javaScriptResultTooLarge:
            "The browser JavaScript result exceeded the bounded output limit."
        case .invalidFetchResponse:
            "WebKit returned an invalid fetch response."
        case let .fetchBodyTooLarge(actualBytes, maximumBytes):
            if let actualBytes {
                "The fetched response is \(actualBytes) bytes, exceeding the \(maximumBytes)-byte single-file limit."
            } else {
                "The fetched response exceeded the \(maximumBytes)-byte single-file limit."
            }
        case .invalidFetchBodyEncoding:
            "WebKit returned an invalid encoded fetch body."
        }
    }
}
