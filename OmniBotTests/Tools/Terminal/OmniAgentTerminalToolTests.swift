import Foundation
import Testing
@testable import Via_Vera

@Suite("Agent terminal tools")
struct OmniAgentTerminalToolTests {
    @Test("Long terminal output is preserved as an offload artifact")
    func longOutputCreatesArtifact() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let output = String(repeating: "terminal-output-line\n", count: 300)
        let executionID = UUID()
        let executor = makeToolExecutor(paths: temporary.paths) { _ in
            OmniTerminalCommandResult(
                executionID: executionID,
                processIdentifier: 44,
                exitCode: 0,
                standardOutput: output,
                standardError: "",
                duration: .milliseconds(5)
            )
        }
        let runID = UUID()
        let conversationID = UUID()

        let result = try await executeTool(
            "terminal_execute",
            arguments: titledArguments("Run verbose command", [
                "command": .string("verbose-command"),
            ]),
            using: executor,
            paths: temporary.paths,
            runID: runID,
            conversationID: conversationID
        )

        let artifact = try #require(result.artifacts.first)
        #expect(result.artifacts.count == 1)
        #expect(result.workspaceID == conversationID.uuidString)
        #expect(artifact.uri.hasPrefix("omnibot://offloads/\(runID.uuidString)/"))
        #expect(artifact.sourceTool == "terminal_execute")
        #expect(try String(contentsOfFile: artifact.hostPath, encoding: .utf8) == output)
        #expect(result.metadata["terminalOutputArtifactCreated"] == .bool(true))
        #expect(result.metadata["terminalOutputOffloadTruncated"] == .bool(false))
        let modelContent = try result.modelContent()
        #expect(!modelContent.contains(temporary.root.path))
    }

    @Test("Logical sessions preserve working directory and environment")
    func logicalSessionState() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let probe = TerminalSessionProbe()
        let executor = makeToolExecutor(paths: temporary.paths) { request in
            try await probe.run(request)
        }
        let conversationID = UUID()

        let start = try await executeTool(
            "terminal_session_start",
            arguments: titledArguments("Start shell", [
                "working_directory": .string("/workspace"),
                "environment": .object(["BASE": .string("one")]),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: conversationID
        )
        let sessionID = try #require(start.metadata["sessionID"]?.stringValue)

        let first = try await executeTool(
            "terminal_session_exec",
            arguments: titledArguments("Change directory", [
                "session_id": .string(sessionID),
                "command": .string("cd sub"),
                "environment": .object(["DELTA": .string("two")]),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: conversationID
        )
        #expect(first.content == "changed")
        #expect(first.metadata["workingDirectory"] == .string("/workspace/sub"))

        _ = try await executeTool(
            "terminal_session_exec",
            arguments: titledArguments("Print directory", [
                "session_id": .string(sessionID),
                "command": .string("pwd"),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: conversationID
        )

        let requests = await probe.capturedRequests()
        #expect(requests.count == 2)
        #expect(requests.last?.workingDirectory == "/workspace/sub")
        #expect(requests.last?.environment["BASE"] == "one")
        #expect(requests.last?.environment["DELTA"] == "two")
    }

    @Test("Logical sessions cannot be accessed from another conversation")
    func logicalSessionsAreConversationScoped() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let probe = TerminalSessionProbe()
        let executor = makeToolExecutor(paths: temporary.paths) { request in
            try await probe.run(request)
        }
        let ownerConversationID = UUID()
        let otherConversationID = UUID()

        let start = try await executeTool(
            "terminal_session_start",
            arguments: titledArguments("Start scoped shell"),
            using: executor,
            paths: temporary.paths,
            conversationID: ownerConversationID
        )
        let sessionID = try #require(start.metadata["sessionID"]?.stringValue)

        let read = try await executeTool(
            "terminal_session_read",
            arguments: titledArguments("Read foreign shell", [
                "session_id": .string(sessionID),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: otherConversationID
        )
        let execute = try await executeTool(
            "terminal_session_exec",
            arguments: titledArguments("Use foreign shell", [
                "session_id": .string(sessionID),
                "command": .string("pwd"),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: otherConversationID
        )
        let stop = try await executeTool(
            "terminal_session_stop",
            arguments: titledArguments("Stop foreign shell", [
                "session_id": .string(sessionID),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: otherConversationID
        )

        for result in [read, execute, stop] {
            #expect(result.isError)
            #expect(result.content.contains("different conversation"))
        }
        #expect(await probe.capturedRequests().isEmpty)

        let ownerRead = try await executeTool(
            "terminal_session_read",
            arguments: titledArguments("Read owned shell", [
                "session_id": .string(sessionID),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: ownerConversationID
        )
        #expect(!ownerRead.isError)
    }

    @Test("Idle logical sessions expire")
    func logicalSessionsExpire() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let limits = OmniAgentToolLimits(terminalSessionIdleTimeoutSeconds: 0.001)
        let executor = makeToolExecutor(paths: temporary.paths, limits: limits)
        let conversationID = UUID()
        let start = try await executeTool(
            "terminal_session_start",
            arguments: titledArguments("Start short-lived shell"),
            using: executor,
            paths: temporary.paths,
            conversationID: conversationID
        )
        let sessionID = try #require(start.metadata["sessionID"]?.stringValue)
        try await Task.sleep(for: .milliseconds(30))

        let read = try await executeTool(
            "terminal_session_read",
            arguments: titledArguments("Read expired shell", [
                "session_id": .string(sessionID),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: conversationID
        )
        #expect(read.isError)
        #expect(read.content.contains("expired"))
    }

    @Test("Commands and environments use UTF-8 byte limits")
    func terminalInputByteLimits() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let limits = OmniAgentToolLimits(
            maximumCommandCharacters: 100,
            maximumCommandBytes: 8,
            maximumEnvironmentVariables: 1,
            maximumEnvironmentValueBytes: 32,
            maximumEnvironmentBytes: 8
        )
        let executor = makeToolExecutor(paths: temporary.paths, limits: limits)

        let command = try await executeTool(
            "terminal_execute",
            arguments: titledArguments("Reject byte-heavy command", [
                "command": .string("💥💥💥"),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(command.isError)
        #expect(command.content.contains("12 UTF-8 bytes"))

        let count = try await executeTool(
            "terminal_execute",
            arguments: titledArguments("Reject too many variables", [
                "command": .string("true"),
                "environment": .object(["A": .string("1"), "B": .string("2")]),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(count.isError)
        #expect(count.content.contains("1-variable limit"))

        let bytes = try await executeTool(
            "terminal_execute",
            arguments: titledArguments("Reject large environment", [
                "command": .string("true"),
                "environment": .object(["A": .string("123456")]),
            ]),
            using: executor,
            paths: temporary.paths
        )
        #expect(bytes.isError)
        #expect(bytes.content.contains("8-byte UTF-8 limit"))
    }

    @Test("Session environment limits apply after persistent updates are merged")
    func mergedSessionEnvironmentIsBounded() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let probe = TerminalSessionProbe()
        let limits = OmniAgentToolLimits(maximumEnvironmentVariables: 1)
        let executor = makeToolExecutor(paths: temporary.paths, limits: limits) { request in
            try await probe.run(request)
        }
        let conversationID = UUID()
        let start = try await executeTool(
            "terminal_session_start",
            arguments: titledArguments("Start bounded shell", [
                "environment": .object(["BASE": .string("one")]),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: conversationID
        )
        let sessionID = try #require(start.metadata["sessionID"]?.stringValue)

        let result = try await executeTool(
            "terminal_session_exec",
            arguments: titledArguments("Reject merged environment", [
                "session_id": .string(sessionID),
                "command": .string("true"),
                "environment": .object(["EXTRA": .string("two")]),
            ]),
            using: executor,
            paths: temporary.paths,
            conversationID: conversationID
        )

        #expect(result.isError)
        #expect(result.content.contains("1-variable limit"))
        #expect(await probe.capturedRequests().isEmpty)
    }

    @Test("Cancelling an agent run cancels its active terminal command")
    func runCancellationPropagates() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let probe = CancellableTerminalProbe()
        let executor = makeToolExecutor(paths: temporary.paths) { request in
            try await probe.run(request)
        }
        let runID = UUID()
        let execution = Task {
            try await executeTool(
                "terminal_execute",
                arguments: titledArguments("Long command", [
                    "command": .string("sleep 30"),
                ]),
                using: executor,
                paths: temporary.paths,
                runID: runID
            )
        }

        #expect(await waitForTerminalProbeToStart(probe))
        await executor.cancel(runID: runID)

        do {
            _ = try await execution.value
            Issue.record("Expected terminal execution to throw CancellationError")
        } catch is CancellationError {
            // Expected: AgentRunner cancellation reaches the injected runtime command.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
        #expect(await probe.wasCancelled())
    }

    @Test("Stopping the current tool returns an interrupted result without cancelling the run")
    func currentToolCancellationBecomesResult() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let probe = CancellableTerminalProbe()
        let executor = makeToolExecutor(paths: temporary.paths) { request in
            try await probe.run(request)
        }
        let runID = UUID()
        let callID = "current-terminal-call"
        let execution = Task {
            try await executeTool(
                "terminal_execute",
                arguments: titledArguments("Long command", [
                    "command": .string("sleep 30"),
                ]),
                using: executor,
                paths: temporary.paths,
                runID: runID,
                callID: callID
            )
        }

        #expect(await waitForTerminalProbeToStart(probe))
        #expect(await executor.cancelCurrentTool(
            runID: runID,
            callID: "another-call"
        ) == false)
        #expect(await executor.cancelCurrentTool(runID: runID, callID: callID))

        let result = try await execution.value
        #expect(result.isError)
        #expect(result.content.contains("用户已停止当前工具调用"))
        #expect(result.metadata["interrupted"] == .bool(true))
        #expect(await probe.wasCancelled())
    }
}

private func waitForTerminalProbeToStart(
    _ probe: CancellableTerminalProbe,
    timeout: Duration = .seconds(1)
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await probe.hasStarted() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await probe.hasStarted()
}

private actor TerminalSessionProbe {
    private var requests: [OmniTerminalCommandRequest] = []

    func run(_ request: OmniTerminalCommandRequest) async throws -> OmniTerminalCommandResult {
        requests.append(request)
        let marker = try marker(in: request.command)
        let changedDirectory = request.command.contains("cd sub")
        let output = changedDirectory
            ? "changed\n\(marker)/workspace/sub\n"
            : "\(request.workingDirectory)\n\(marker)\(request.workingDirectory)\n"
        return OmniTerminalCommandResult(
            executionID: UUID(),
            processIdentifier: 42,
            exitCode: 0,
            standardOutput: output,
            standardError: "",
            duration: .milliseconds(5)
        )
    }

    func capturedRequests() -> [OmniTerminalCommandRequest] {
        requests
    }

    private func marker(in command: String) throws -> String {
        let prefix = "__OMNIBOT_PWD_"
        guard let prefixRange = command.range(of: prefix),
              let suffixRange = command[prefixRange.upperBound...].range(of: "__") else {
            throw OmniAgentToolError("Session command did not contain a PWD marker.")
        }
        return String(command[prefixRange.lowerBound..<suffixRange.upperBound])
    }
}

private actor CancellableTerminalProbe {
    private var started = false
    private var cancelled = false

    func run(_ request: OmniTerminalCommandRequest) async throws -> OmniTerminalCommandResult {
        started = true
        do {
            try await Task.sleep(nanoseconds: 30_000_000_000)
        } catch is CancellationError {
            cancelled = true
            throw CancellationError()
        }
        return OmniTerminalCommandResult(
            executionID: UUID(),
            processIdentifier: 43,
            exitCode: 0,
            standardOutput: "",
            standardError: "",
            duration: .seconds(30)
        )
    }

    func hasStarted() -> Bool {
        started
    }

    func wasCancelled() -> Bool {
        cancelled
    }
}
