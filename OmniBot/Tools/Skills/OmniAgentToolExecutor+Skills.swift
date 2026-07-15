import Foundation

extension OmniAgentToolExecutor {
    func listSkills(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let query = try arguments.optionalString("query", default: "", maximumLength: 1_000) ?? ""
        let limit = try arguments.integer("limit", default: 50, range: 1...200) ?? 50
        let skills = try await skillStore.list(query: query, limit: limit)
        let items = skills.map { skill in
            AgentValue.object([
                "id": .string(skill.id),
                "name": .string(skill.name),
                "description": .string(skill.description),
                "enabled": .bool(skill.enabled),
                "rootPath": .string(skill.rootPath),
                "skillFilePath": .string(skill.skillFilePath),
                "capabilities": .array(skill.capabilities.map(AgentValue.string)),
                "metadata": .object(skill.metadata.mapValues(AgentValue.string)),
            ])
        }
        return AgentToolExecutionResult(
            content: skills.isEmpty
                ? "No matching installed skills."
                : "Found \(skills.count) installed skill(s).",
            metadata: [
                "query": .string(query),
                "count": .number(Double(skills.count)),
                "skillsRoot": .string("/workspace/.omnibot/skills"),
                "items": .array(items),
            ],
            workspaceID: "shared"
        )
    }

    func readSkill(_ arguments: OmniToolArguments) async throws -> AgentToolExecutionResult {
        let identifier = try arguments.requiredString("skillId", maximumLength: 4_096)
        let maximumCharacters = try arguments.integer(
            "maxChars",
            default: 16_000,
            range: 512...64_000
        ) ?? 16_000
        let skill = try await skillStore.read(
            identifier,
            maximumCharacters: maximumCharacters
        )
        let skillURL = try workspaceURL(forShellPath: skill.entry.skillFilePath)
        let artifact = try resourceProtocol.artifact(
            for: skillURL,
            sourceTool: "skills_read",
            title: "\(skill.entry.name) SKILL.md"
        )
        return AgentToolExecutionResult(
            content: skill.promptSummary(maximumCharacters: maximumCharacters),
            metadata: [
                "id": .string(skill.entry.id),
                "name": .string(skill.entry.name),
                "description": .string(skill.entry.description),
                "rootPath": .string(skill.entry.rootPath),
                "skillFilePath": .string(skill.entry.skillFilePath),
                "scriptsPath": skill.scriptsPath.map(AgentValue.string) ?? .null,
                "assetsPath": skill.assetsPath.map(AgentValue.string) ?? .null,
                "references": .array(skill.referencePaths.map(AgentValue.string)),
                "frontmatter": .object(skill.frontmatter.mapValues(AgentValue.string)),
                "uri": .string(artifact.uri),
            ],
            artifacts: [artifact],
            workspaceID: "shared"
        )
    }

    private func workspaceURL(forShellPath path: String) throws -> URL {
        guard path == "/workspace" || path.hasPrefix("/workspace/") else {
            throw OmniAgentToolError("Skill path is outside /workspace: \(path)")
        }
        let relativePath = try descriptorFileSystem.parse(path)
        return relativePath.components.reduce(paths.root) { partial, component in
            partial.appending(path: component)
        }
        .standardizedFileURL
    }
}
