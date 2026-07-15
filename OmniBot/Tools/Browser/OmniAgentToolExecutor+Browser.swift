import Foundation

extension OmniAgentToolExecutor {
    func executeBrowser(
        _ arguments: OmniToolArguments,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolExecutionResult {
        guard let browserSession else {
            return AgentToolExecutionResult(
                content: "The WebKit browser session is unavailable in this executor configuration.",
                isError: true,
                metadata: [
                    "engine": .string("WebKit.WebPage"),
                    "safariAppControlled": .bool(false),
                    "sharesSafariCookies": .bool(false),
                    "available": .bool(false),
                ]
            )
        }
        let rawAction = try arguments.requiredString("action", maximumLength: 64)
        guard let action = AppleBrowserAction(rawValue: rawAction) else {
            throw AppleBrowserError.invalidAction(rawAction)
        }
        return try await browserSession.execute(
            action: action,
            arguments: arguments,
            context: context,
            resourceProtocol: resourceProtocol
        )
    }
}
