import Foundation
import Testing
@testable import Via_Vera

@Suite("Apple WebKit browser session")
@MainActor
struct AppleBrowserSessionTests {
    @Test("Tab ids are monotonic while simultaneous tabs stay bounded")
    func tabIdentifiersAndLimit() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)

        #expect(try session.createTab().id == 1)
        #expect(try session.createTab().id == 2)
        #expect(try session.createTab().id == 3)
        #expect(throws: AppleBrowserError.self) {
            _ = try session.createTab()
        }

        session.tabs[2] = nil
        #expect(try session.createTab().id == 4)
        #expect(session.tabs.count == 3)
    }

    @Test("Changing conversations closes tabs and rotates ephemeral website data")
    func conversationIsolation() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)
        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)
        let firstConversationID = UUID()
        let secondConversationID = UUID()
        let originalDataStore = session.websiteDataStore
        let arguments = try browserArguments()

        let firstResult = try await session.execute(
            action: .listTabs,
            arguments: arguments,
            context: AgentToolExecutionContext(
                runID: UUID(),
                conversationID: firstConversationID,
                workspaceURL: temporary.paths.root
            ),
            resourceProtocol: resourceProtocol
        )
        #expect(session.boundConversationID == firstConversationID)
        #expect(session.websiteDataStore === originalDataStore)
        #expect(firstResult.metadata["websiteDataStorePolicy"] == .string(
            AppleBrowserWebsiteDataStorePolicy.nonPersistentPerConversation.rawValue
        ))

        #expect(try session.createTab().id == 1)
        #expect(try session.createTab().id == 2)
        let secondResult = try await session.execute(
            action: .listTabs,
            arguments: arguments,
            context: AgentToolExecutionContext(
                runID: UUID(),
                conversationID: secondConversationID,
                workspaceURL: temporary.paths.root
            ),
            resourceProtocol: resourceProtocol
        )

        #expect(session.boundConversationID == secondConversationID)
        #expect(session.tabs.isEmpty)
        #expect(session.activeTabID == nil)
        #expect(session.nextTabID == 1)
        #expect(session.websiteDataStore !== originalDataStore)
        #expect(secondResult.content.contains("Listed 0 browser tab"))
        #expect(secondResult.metadata["manualTakeoverSupported"] == .bool(true))

        let secondDataStore = session.websiteDataStore
        session.bind(to: secondConversationID)
        #expect(session.websiteDataStore === secondDataStore)
    }

    @Test("Scheme-less browser URLs prefer HTTPS")
    func httpsIsPreferred() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)

        #expect(try session.normalizedWebURL("example.com/path").absoluteString == "https://example.com/path")
        #expect(try session.normalizedWebURL("http://example.com").scheme == "http")
        #expect(throws: AppleBrowserError.self) {
            _ = try session.normalizedWebURL("file:///tmp/private")
        }
    }

    @Test("Visible browser presentation reuses the conversation WebKit tab")
    func visiblePresentationSharesSession() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)
        let conversationID = UUID()

        let tab = try session.prepareForPresentation(conversationID: conversationID)
        let snapshot = session.presentationSnapshot(for: conversationID)

        #expect(snapshot.activeTab === tab)
        #expect(snapshot.activeTabID == tab.id)
        #expect(snapshot.tabs.map(\.id) == [tab.id])
        #expect(session.boundConversationID == conversationID)

        tab.lastRiskReport = AppleBrowserRiskReport(
            detected: true,
            signals: ["captcha"]
        )
        await session.refreshRiskFromPresentation(conversationID: conversationID)
        #expect(!tab.lastRiskReport.detected)
    }

    @Test("All Android-compatible browser actions remain represented")
    func actionContract() {
        #expect(AppleBrowserAction.allCases.count == 23)
        #expect(AppleBrowserAction(rawValue: "wait_for_selector") == .waitForSelector)
        #expect(AppleBrowserAction(rawValue: "scroll_and_collect") == .scrollAndCollect)
    }

    @Test("Risk challenges block synthetic interaction with structured metadata")
    func riskChallengeBlocksInteraction() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)
        let tab = try session.createTab()
        tab.lastRiskReport = AppleBrowserRiskReport(
            detected: true,
            signals: ["captcha"]
        )

        let result = session.blockedByRiskChallenge(tab: tab, action: .click)

        #expect(result.isError)
        #expect(result.metadata["riskChallengeDetected"] == .bool(true))
        #expect(result.metadata["automationStopped"] == .bool(true))
        #expect(result.metadata["manualTakeoverSupported"] == .bool(true))
        #expect(result.content.contains("complete the challenge manually"))
        #expect(result.content.contains("same WebKit session"))
    }

    @Test("Cookie name filtering follows keywords and fuzzy contract with a hard limit")
    func cookieNameFiltering() {
        let names = ["session_auth", "AUTH_SESSION", "auth", "other"]

        let fuzzy = AppleBrowserSession.filterCookieNames(
            names,
            keywords: "  AUTH   session ",
            fuzzy: true
        )
        #expect(fuzzy.matchingIndices == [0, 1])
        #expect(fuzzy.keywords == ["auth", "session"])
        #expect(fuzzy.totalMatched == 2)
        #expect(!fuzzy.truncated)

        let exact = AppleBrowserSession.filterCookieNames(
            names,
            keywords: "AUTH other",
            fuzzy: false,
            limit: 1
        )
        #expect(exact.matchingIndices == [2])
        #expect(exact.totalMatched == 2)
        #expect(exact.truncated)

        let bounded = AppleBrowserSession.filterCookieNames(
            (0..<205).map { "cookie-\($0)" },
            keywords: nil,
            fuzzy: true
        )
        #expect(bounded.matchingIndices.count == 200)
        #expect(bounded.totalMatched == 205)
        #expect(bounded.truncated)
    }

    @Test("Type target prefers selector, then coordinates, then active element")
    func typeTargetContract() throws {
        let selector = try AppleBrowserSession.typeTarget(for: browserArguments([
            "selector": .string("  #search  "),
            "coordinate_x": .number(40),
        ]))
        #expect(selector == AppleBrowserTypeTarget(
            kind: .selector,
            selector: "#search",
            x: nil,
            y: nil
        ))

        let coordinates = try AppleBrowserSession.typeTarget(for: browserArguments([
            "coordinate_x": .number(40),
            "coordinate_y": .number(80),
        ]))
        #expect(coordinates == AppleBrowserTypeTarget(
            kind: .coordinates,
            selector: nil,
            x: 40,
            y: 80
        ))

        let activeElement = try AppleBrowserSession.typeTarget(for: browserArguments())
        #expect(activeElement.kind == .activeElement)
        #expect(throws: AppleBrowserError.self) {
            _ = try AppleBrowserSession.typeTarget(for: browserArguments([
                "coordinate_x": .number(40),
            ]))
        }
        #expect(AppleBrowserSession.typeScriptSupportsCoordinateAndActiveElementTargets)
    }

    @Test("Fetch filenames and MIME types are normalized before persistence")
    func fetchedFileNameNormalization() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)

        #expect(session.normalizedMIMEType("Application/JSON; charset=utf-8") == "application/json")
        #expect(session.normalizedMIMEType("invalid mime") == "application/octet-stream")
        #expect(session.safeFetchFileName("../../secret?.pdf", mimeType: "application/pdf") == "secret_.pdf")
        #expect(session.safeFetchFileName("payload.exe", mimeType: "image/png") == "payload.png")
        #expect(
            session.suggestedFetchFileName(
                contentDisposition: "attachment; filename*=UTF-8''Quarterly%20Report.pdf",
                finalURL: "https://example.com/fallback"
            ) == "Quarterly Report.pdf"
        )
        #expect(
            session.suggestedFetchFileName(
                contentDisposition: "attachment; filename=\"part;two.txt\"",
                finalURL: "https://example.com/fallback"
            ) == "part;two.txt"
        )
    }

    @Test("Fetched bytes persist atomically beneath the run browser directory")
    func fetchedResponseArtifactPersistence() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)
        let runID = UUID()
        let context = AgentToolExecutionContext(
            runID: runID,
            conversationID: UUID(),
            workspaceURL: temporary.paths.root
        )
        let data = Data("{\"status\":\"ok\"}".utf8)

        let artifact = try session.persistFetchedResponse(
            data: data,
            suggestedFileName: "../result.json",
            mimeType: "application/json",
            context: context,
            resourceProtocol: AgentResourceProtocol(paths: temporary.paths)
        )

        #expect(artifact.uri.hasPrefix("omnibot://browser/\(runID.uuidString)/"))
        #expect(artifact.fileName.hasSuffix("-result.json"))
        #expect(artifact.mimeType == "application/json")
        #expect(try Data(contentsOf: URL(fileURLWithPath: artifact.hostPath)) == data)
        #expect(session.textPreview(for: data, mimeType: "application/json")?.text == "{\"status\":\"ok\"}")
    }

    @Test("A background symlink swap cannot redirect browser artifact writes")
    func browserArtifactSymlinkFlipper() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let outside = temporary.root.appending(
            path: "browser-escape-target",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let canary = outside.appending(path: "canary.txt")
        try "BROWSER_ESCAPE_CANARY".write(to: canary, atomically: true, encoding: .utf8)
        let initialOutsideNames = try Set(
            FileManager.default.contentsOfDirectory(atPath: outside.path)
        )

        let session = AppleBrowserSession(paths: temporary.paths)
        let context = AgentToolExecutionContext(
            runID: UUID(),
            conversationID: UUID(),
            workspaceURL: temporary.paths.root
        )
        let resourceProtocol = AgentResourceProtocol(paths: temporary.paths)
        let data = Data("browser workspace payload".utf8)
        let flipper = try WorkspaceSymlinkFlipper(
            liveDirectory: temporary.paths.browserDirectory,
            escapeTarget: outside
        )

        do {
            try await flipper.waitForSwaps()
            for index in 0..<80 {
                _ = try? session.persistFetchedResponse(
                    data: data,
                    suggestedFileName: "race-\(index).txt",
                    mimeType: "text/plain",
                    context: context,
                    resourceProtocol: resourceProtocol
                )
            }
        } catch {
            try? await flipper.stop()
            throw error
        }
        try await flipper.stop()

        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: outside.path)) == initialOutsideNames)
        #expect(try String(contentsOf: canary, encoding: .utf8) == "BROWSER_ESCAPE_CANARY")

        let artifact = try session.persistFetchedResponse(
            data: data,
            suggestedFileName: "after-race.txt",
            mimeType: "text/plain",
            context: context,
            resourceProtocol: resourceProtocol
        )
        #expect(try Data(contentsOf: URL(fileURLWithPath: artifact.hostPath)) == data)
    }

    @Test("Fetch bridge decodes bounded base64 and reports oversized bodies")
    func fetchedResponseBridgeValidation() throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let session = AppleBrowserSession(paths: temporary.paths)
        let data = Data("hello".utf8)

        let decoded = try session.decodeFetchedResponse(
            [
                "requestedUrl": "https://example.com/file.txt",
                "finalUrl": "https://cdn.example.com/file.txt",
                "status": 200,
                "ok": true,
                "redirected": true,
                "contentType": "text/plain",
                "size": data.count,
                "base64": data.base64EncodedString(),
            ],
            requestedURL: "https://example.com/file.txt"
        )
        #expect(decoded.data == data)
        #expect(decoded.statusCode == 200)

        #expect(throws: AppleBrowserError.self) {
            _ = try session.decodeFetchedResponse(
                [
                    "error": "body_too_large",
                    "actualBytes": AppleBrowserSession.maximumFetchArtifactBytes + 1,
                ],
                requestedURL: "https://example.com/large.bin"
            )
        }
    }

    private func browserArguments(
        _ values: [String: AgentValue] = [:]
    ) throws -> OmniToolArguments {
        var arguments = values
        arguments["tool_title"] = .string("Browser test")
        let data = try JSONEncoder().encode(AgentValue.object(arguments))
        return try OmniToolArguments(call: AgentToolCall(
            id: UUID().uuidString,
            name: "browser_use",
            arguments: String(decoding: data, as: UTF8.self)
        ))
    }
}
