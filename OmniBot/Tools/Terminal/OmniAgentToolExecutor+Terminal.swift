import Foundation

extension OmniAgentToolExecutor {
    func executeTerminal(
        _ arguments: OmniToolArguments,
        callID: String,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        let command = try arguments.requiredString(
            "command",
            maximumLength: limits.maximumCommandCharacters
        )
        try validateCommand(command)
        let workingDirectory = try arguments.optionalString(
            "working_directory",
            default: "/workspace",
            maximumLength: 4_096
        ) ?? "/workspace"
        try validateGuestWorkingDirectory(workingDirectory)
        let environment = try terminalEnvironment(arguments)
        let timeout = try arguments.integer(
            "timeout_seconds",
            default: 120,
            range: 1...600
        ) ?? 120

        let result = try await runTerminalCommand(
            OmniTerminalCommandRequest(
                command: command,
                workingDirectory: workingDirectory,
                environment: environment,
                timeout: .seconds(timeout)
            ),
            runID: context.runID,
            callID: callID,
            sessionID: nil
        )
        let output = terminalOutput(
            standardOutput: result.standardOutput,
            standardError: result.standardError,
            failureDescription: result.failureDescription
        )
        let bounded = boundedText(
            output,
            maximumCharacters: limits.maximumTerminalOutputCharacters
        )
        let offload = terminalOutputOffload(
            output,
            executionID: result.executionID,
            sourceTool: "terminal_execute",
            context: context
        )
        var metadata = terminalMetadata(
            result,
            workingDirectory: workingDirectory,
            outputTruncated: bounded.truncated
        )
        addTerminalOffloadMetadata(offload, to: &metadata)
        return AgentToolExecutionResult(
            content: bounded.text,
            isError: !result.succeeded,
            metadata: metadata,
            artifacts: offload.artifacts,
            workspaceID: offload.artifacts.isEmpty ? nil : "shared"
        )
    }

    func startTerminalSession(
        _ arguments: OmniToolArguments,
        context: AgentToolExecutionContext
    ) throws -> AgentToolExecutionResult {
        let now = Date()
        pruneExpiredTerminalSessions(now: now)
        guard terminalSessions.count < limits.maximumTerminalSessions else {
            throw OmniAgentToolError(
                "Terminal session limit reached (\(limits.maximumTerminalSessions)). Stop an existing session first."
            )
        }
        let workingDirectory = try arguments.optionalString(
            "working_directory",
            default: "/workspace",
            maximumLength: 4_096
        ) ?? "/workspace"
        try validateGuestWorkingDirectory(workingDirectory)
        let environment = try terminalEnvironment(arguments)
        let session = OmniTerminalSession(
            conversationID: context.conversationID,
            workingDirectory: workingDirectory,
            environment: environment,
            lastAccessAt: now
        )
        terminalSessions[session.id] = session
        return AgentToolExecutionResult(
            content: "Started logical terminal session \(session.id.uuidString) in \(workingDirectory).",
            metadata: [
                "sessionID": .string(session.id.uuidString),
                "workingDirectory": .string(workingDirectory),
                "environmentCount": .number(Double(environment.count)),
            ]
        )
    }

    func executeInTerminalSession(
        _ arguments: OmniToolArguments,
        callID: String,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        let sessionID = try terminalSessionID(arguments)
        var session = try terminalSession(
            identifiedBy: sessionID,
            context: context,
            now: Date()
        )
        guard session.activeExecutionID == nil else {
            throw OmniAgentToolError(
                "Terminal session \(sessionID.uuidString) is already executing a command."
            )
        }

        let command = try arguments.requiredString(
            "command",
            maximumLength: limits.maximumCommandCharacters
        )
        try validateCommand(command)
        let environmentUpdates = try terminalEnvironment(arguments)
        session.environment.merge(environmentUpdates) { _, newValue in newValue }
        try validateEnvironment(session.environment)
        let timeout = try arguments.integer(
            "timeout_seconds",
            default: 120,
            range: 1...600
        ) ?? 120

        let marker = "__OMNIBOT_PWD_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
        let wrappedCommand = """
        \(command)
        __omnibot_status=$?
        printf '\\n\(marker)%s\\n' "$PWD"
        exit "$__omnibot_status"
        """
        try validateCommand(wrappedCommand, parameterName: "wrapped command")
        session.lastAccessAt = Date()
        terminalSessions[sessionID] = session
        let result = try await runTerminalCommand(
            OmniTerminalCommandRequest(
                command: wrappedCommand,
                workingDirectory: session.workingDirectory,
                environment: session.environment,
                timeout: .seconds(timeout)
            ),
            runID: context.runID,
            callID: callID,
            sessionID: sessionID
        )

        let parsed = parsePWDMarker(marker, in: result.standardOutput)
        let output = terminalOutput(
            standardOutput: parsed.output,
            standardError: result.standardError,
            failureDescription: result.failureDescription
        )
        let bounded = boundedText(
            output,
            maximumCharacters: limits.maximumTerminalOutputCharacters
        )

        if var updatedSession = terminalSessions[sessionID] {
            if let workingDirectory = parsed.workingDirectory,
               isValidGuestWorkingDirectory(workingDirectory) {
                updatedSession.workingDirectory = workingDirectory
            }
            updatedSession.lastOutput = bounded.text
            updatedSession.lastExitCode = result.exitCode
            updatedSession.lastOutputWasTruncated = bounded.truncated
            updatedSession.lastAccessAt = Date()
            terminalSessions[sessionID] = updatedSession
        }

        let finalWorkingDirectory = terminalSessions[sessionID]?.workingDirectory
            ?? parsed.workingDirectory
            ?? session.workingDirectory
        var metadata = terminalMetadata(
            result,
            workingDirectory: finalWorkingDirectory,
            outputTruncated: bounded.truncated
        )
        metadata["sessionID"] = .string(sessionID.uuidString)
        let offload = terminalOutputOffload(
            output,
            executionID: result.executionID,
            sourceTool: "terminal_session_exec",
            context: context
        )
        addTerminalOffloadMetadata(offload, to: &metadata)
        return AgentToolExecutionResult(
            content: bounded.text,
            isError: !result.succeeded,
            metadata: metadata,
            artifacts: offload.artifacts,
            workspaceID: offload.artifacts.isEmpty ? nil : "shared"
        )
    }

    func readTerminalSession(
        _ arguments: OmniToolArguments,
        context: AgentToolExecutionContext
    ) throws -> AgentToolExecutionResult {
        let sessionID = try terminalSessionID(arguments)
        let session = try terminalSession(
            identifiedBy: sessionID,
            context: context,
            now: Date()
        )
        let offset = try arguments.integer(
            "offset_chars",
            default: 0,
            range: 0...10_000_000
        ) ?? 0
        let requestedMaximum = try arguments.integer(
            "max_chars",
            default: min(32_768, limits.maximumTerminalOutputCharacters),
            range: 1...131_072
        ) ?? min(32_768, limits.maximumTerminalOutputCharacters)
        let maximum = min(requestedMaximum, limits.maximumTerminalOutputCharacters)
        let total = session.lastOutput.count
        let safeOffset = min(offset, total)
        let start = session.lastOutput.index(
            session.lastOutput.startIndex,
            offsetBy: safeOffset
        )
        let end = session.lastOutput.index(
            start,
            offsetBy: min(maximum, total - safeOffset)
        )
        let content = String(session.lastOutput[start..<end])
        return AgentToolExecutionResult(
            content: content.isEmpty ? "(no stored output)" : content,
            metadata: [
                "sessionID": .string(sessionID.uuidString),
                "workingDirectory": .string(session.workingDirectory),
                "lastExitCode": session.lastExitCode.map { .number(Double($0)) } ?? .null,
                "active": .bool(session.activeExecutionID != nil),
                "offsetChars": .number(Double(safeOffset)),
                "nextOffsetChars": .number(Double(safeOffset + content.count)),
                "totalChars": .number(Double(total)),
                "storedOutputTruncated": .bool(session.lastOutputWasTruncated),
            ]
        )
    }

    func stopTerminalSession(
        _ arguments: OmniToolArguments,
        context: AgentToolExecutionContext
    ) throws -> AgentToolExecutionResult {
        let sessionID = try terminalSessionID(arguments)
        let session = try terminalSession(
            identifiedBy: sessionID,
            context: context,
            now: Date()
        )
        terminalSessions[sessionID] = nil
        if let executionID = session.activeExecutionID {
            activeTerminalCommands[executionID]?.task.cancel()
        }
        return AgentToolExecutionResult(
            content: "Stopped logical terminal session \(sessionID.uuidString).",
            metadata: ["sessionID": .string(sessionID.uuidString)]
        )
    }

    private func runTerminalCommand(
        _ request: OmniTerminalCommandRequest,
        runID: UUID,
        callID: String,
        sessionID: UUID?
    ) async throws -> OmniTerminalCommandResult {
        try Task.checkCancellation()
        let executionID = UUID()
        let outputHandler = terminalOutputHandler
        let task = Task {
            try await commandRunner.execute(request) { line, isStandardError in
                outputHandler?(runID, callID, line, isStandardError)
            }
        }
        activeTerminalCommands[executionID] = OmniActiveTerminalCommand(
            runID: runID,
            callID: callID,
            sessionID: sessionID,
            task: task
        )
        if let sessionID, var session = terminalSessions[sessionID] {
            session.activeExecutionID = executionID
            terminalSessions[sessionID] = session
        }
        defer {
            activeTerminalCommands[executionID] = nil
            if let sessionID,
               var session = terminalSessions[sessionID],
               session.activeExecutionID == executionID {
                session.activeExecutionID = nil
                session.lastAccessAt = Date()
                terminalSessions[sessionID] = session
            }
        }

        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try checkForUserToolCancellation(runID: runID, callID: callID)
        try Task.checkCancellation()
        return result
    }

    private func terminalSessionID(_ arguments: OmniToolArguments) throws -> UUID {
        let raw = try arguments.requiredString("session_id", maximumLength: 64)
        guard let id = UUID(uuidString: raw) else {
            throw OmniAgentToolError(
                "Invalid parameter 'session_id': expected a UUID returned by terminal_session_start."
            )
        }
        return id
    }

    private func terminalSession(
        identifiedBy sessionID: UUID,
        context: AgentToolExecutionContext,
        now: Date
    ) throws -> OmniTerminalSession {
        guard var session = terminalSessions[sessionID] else {
            throw OmniAgentToolError("Terminal session \(sessionID.uuidString) was not found.")
        }
        guard session.conversationID == context.conversationID else {
            throw OmniAgentToolError(
                "Terminal session \(sessionID.uuidString) belongs to a different conversation."
            )
        }
        if session.activeExecutionID == nil,
           now.timeIntervalSince(session.lastAccessAt) > limits.terminalSessionIdleTimeoutSeconds {
            terminalSessions[sessionID] = nil
            throw OmniAgentToolError(
                "Terminal session \(sessionID.uuidString) expired after being idle."
            )
        }
        session.lastAccessAt = now
        terminalSessions[sessionID] = session
        return session
    }

    private func pruneExpiredTerminalSessions(now: Date) {
        let expiredSessionIDs: [UUID] = terminalSessions.compactMap { element -> UUID? in
            let (sessionID, session) = element
            guard session.activeExecutionID == nil,
                  now.timeIntervalSince(session.lastAccessAt) > limits.terminalSessionIdleTimeoutSeconds else {
                return nil
            }
            return sessionID
        }
        for sessionID in expiredSessionIDs {
            terminalSessions[sessionID] = nil
        }
    }

    private func validateGuestWorkingDirectory(_ path: String) throws {
        guard isValidGuestWorkingDirectory(path) else {
            throw OmniAgentToolError(
                "Invalid guest working directory: expected an absolute, newline-free path."
            )
        }
    }

    private func isValidGuestWorkingDirectory(_ path: String) -> Bool {
        path.hasPrefix("/")
            && !path.contains("\0")
            && !path.contains("\n")
            && !path.contains("\r")
    }

    private func parsePWDMarker(
        _ marker: String,
        in standardOutput: String
    ) -> (output: String, workingDirectory: String?) {
        guard let markerRange = standardOutput.range(of: marker, options: .backwards) else {
            return (standardOutput, nil)
        }
        let pathStart = markerRange.upperBound
        let pathEnd = standardOutput[pathStart...].firstIndex(where: { $0.isNewline })
            ?? standardOutput.endIndex
        let workingDirectory = String(standardOutput[pathStart..<pathEnd])
        var output = String(standardOutput[..<markerRange.lowerBound])
        if output.hasSuffix("\n") {
            output.removeLast()
        }
        return (output, workingDirectory)
    }

    private func terminalMetadata(
        _ result: OmniTerminalCommandResult,
        workingDirectory: String,
        outputTruncated: Bool
    ) -> [String: AgentValue] {
        [
            "executionID": .string(result.executionID.uuidString),
            "processIdentifier": .number(Double(result.processIdentifier)),
            "exitCode": .number(Double(result.exitCode)),
            "durationSeconds": .number(durationSeconds(result.duration)),
            "workingDirectory": .string(workingDirectory),
            "outputTruncated": .bool(outputTruncated),
        ]
    }

    private func terminalOutputOffload(
        _ output: String,
        executionID: UUID,
        sourceTool: String,
        context: AgentToolExecutionContext
    ) -> (
        artifacts: [AgentArtifact],
        originalUTF8Bytes: Int,
        truncated: Bool,
        failed: Bool
    ) {
        let originalUTF8Bytes = output.utf8.count
        guard originalUTF8Bytes > 4_000 else {
            return ([], originalUTF8Bytes, false, false)
        }

        let maximumBytes = 16 * 1_024 * 1_024
        let marker = Data("\n[Terminal offload truncated at 16 MiB.]\n".utf8)
        let wasTruncated = originalUTF8Bytes > maximumBytes
        let data: Data
        if wasTruncated {
            let prefixBudget = maximumBytes - marker.count - 3
            let prefix = String(
                decoding: output.utf8.prefix(prefixBudget),
                as: UTF8.self
            )
            var bounded = Data(prefix.utf8)
            bounded.append(marker)
            data = bounded
        } else {
            data = Data(output.utf8)
        }

        do {
            let directory = try descriptorFileSystem.parse(
                ".omnibot/offloads/\(context.runID.uuidString)"
            )
            let relativeFile = try descriptorFileSystem.atomicallyWriteUnique(
                data,
                in: directory,
                preferredName: "terminal-\(executionID.uuidString).log",
                maximumBytes: maximumBytes
            )
            let fileURL = relativeFile.components.reduce(paths.root) { partial, component in
                partial.appending(path: component)
            }
            let artifact = try resourceProtocol.artifact(
                for: fileURL,
                sourceTool: sourceTool,
                title: "Terminal output"
            )
            return ([artifact], originalUTF8Bytes, wasTruncated, false)
        } catch {
            // The command result remains useful even when a hostile workspace
            // swap or a transient filesystem error prevents publishing the
            // optional transcript artifact.
            return ([], originalUTF8Bytes, wasTruncated, true)
        }
    }

    private func addTerminalOffloadMetadata(
        _ offload: (
            artifacts: [AgentArtifact],
            originalUTF8Bytes: Int,
            truncated: Bool,
            failed: Bool
        ),
        to metadata: inout [String: AgentValue]
    ) {
        guard offload.originalUTF8Bytes > 4_000 else { return }
        metadata["terminalOutputUTF8Bytes"] = .number(Double(offload.originalUTF8Bytes))
        metadata["terminalOutputArtifactCreated"] = .bool(!offload.artifacts.isEmpty)
        metadata["terminalOutputOffloadTruncated"] = .bool(offload.truncated)
        metadata["terminalOutputOffloadFailed"] = .bool(offload.failed)
    }
}
