import Foundation

extension OmniAgentToolExecutor {
    func executeNativeTool(
        _ name: String, arguments: OmniToolArguments, context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        try await NativeToolAgentBridge(paths: paths, store: nativeToolStore)
            .execute(name, arguments: arguments, context: context)
    }
}
