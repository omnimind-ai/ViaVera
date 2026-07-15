import Foundation
@testable import Via_Vera

func makeToolExecutor(
    paths: WorkspacePaths,
    timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!,
    limits: OmniAgentToolLimits = .default,
    memoryLimits: MarkdownMemoryLimits = .default,
    agentPermissionStore: AgentPermissionStore? = nil,
    handler: @escaping OmniTerminalCommandRunner.Handler = { _ in
        OmniTerminalCommandResult(
            executionID: UUID(),
            processIdentifier: 1,
            exitCode: 0,
            standardOutput: "",
            standardError: "",
            duration: .zero
        )
    }
) -> OmniAgentToolExecutor {
    OmniAgentToolExecutor(
        paths: paths,
        memoryStore: MarkdownMemoryStore(
            paths: paths,
            timeZone: timeZone,
            limits: memoryLimits
        ),
        commandRunner: OmniTerminalCommandRunner(handler: handler),
        limits: limits,
        agentPermissionStore: agentPermissionStore,
        appleAlarmService: nil,
        appleCalendarService: nil,
        appleContactsService: nil,
        appleHealthKitService: nil,
        browserSession: nil
    )
}

func executeTool(
    _ name: String,
    arguments: [String: AgentValue],
    using executor: OmniAgentToolExecutor,
    paths: WorkspacePaths,
    runID: UUID = UUID(),
    conversationID: UUID = UUID(),
    callID: String = UUID().uuidString
) async throws -> AgentToolExecutionResult {
    let data = try JSONEncoder().encode(AgentValue.object(arguments))
    let call = AgentToolCall(
        id: callID,
        name: name,
        arguments: String(decoding: data, as: UTF8.self)
    )
    return try await executor.execute(
        call,
        context: AgentToolExecutionContext(
            runID: runID,
            conversationID: conversationID,
            workspaceURL: paths.root
        )
    )
}

func titledArguments(
    _ title: String = "Test tool",
    _ values: [String: AgentValue] = [:]
) -> [String: AgentValue] {
    var result = values
    result["tool_title"] = .string(title)
    return result
}
