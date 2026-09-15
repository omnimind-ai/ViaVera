import Foundation
import Testing
@testable import Via_Vera

@Suite("Built-in native tool skill")
struct BuiltInNativeToolSkillTests {
    @Test("Skills settings show the built-in skill and Agent prompt respects its switch")
    @MainActor
    func settingsAndPrompt() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let store = AgentSkillStore(paths: workspace.paths, builtInSkillsURL: NativeToolTestFixtures.skillDirectory.deletingLastPathComponent())
        let settings = SkillSettingsModel(store: store)
        await settings.load()
        #expect(settings.skills.first?.isBuiltIn == true)
        #expect(settings.skills.first?.displayName == "原生工具制作")
        let context = AgentSystemPromptContext(soul: "", memory: MemoryPromptContext(longTermMemory: "", todayMemory: ""), installedSkills: settings.skills, availableToolNames: ["skills_read", "native_tool_install"], localeIdentifier: "zh_CN")
        #expect(AgentSystemPromptBuilder().build(context).contains("native-tool-builder"))
        #expect(await settings.setEnabled(false, for: "native-tool-builder") == false)
        let disabled = AgentSystemPromptContext(soul: "", memory: MemoryPromptContext(longTermMemory: "", todayMemory: ""), installedSkills: settings.skills, availableToolNames: ["skills_read", "native_tool_install"], localeIdentifier: "zh_CN")
        #expect(!AgentSystemPromptBuilder().build(disabled).contains("native-tool-builder"))
    }

    @Test("Default enablement, protected source, persistent disablement and non-deletability")
    func lifecycle() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let bundle = NativeToolTestFixtures.skillDirectory.deletingLastPathComponent()
        let store = AgentSkillStore(paths: workspace.paths, builtInSkillsURL: bundle)
        let entries = try await store.list()
        let entry = try #require(entries.first(where: { $0.id == "native-tool-builder" }))
        #expect(entry.isBuiltIn)
        #expect(entry.enabled)
        #expect(entry.displayName == "原生工具制作")
        #expect(entry.hasAssets && entry.hasReferences)
        let projection = workspace.paths.skillsDirectory.appending(path: "native-tool-builder/SKILL.md")
        try "FORGED INSTRUCTIONS".write(to: projection, atomically: true, encoding: .utf8)
        let loaded = try await store.read(entry.id)
        #expect(!loaded.bodyMarkdown.contains("FORGED INSTRUCTIONS"))
        #expect(loaded.referencePaths.contains(where: { $0.hasSuffix("package-format.md") }))
        let matches = try await store.resolveMatches(userMessage: "使用 $native-tool-builder 制作一个清单")
        #expect(matches.first?.entry.id == entry.id)
        await #expect(throws: AgentSkillStoreError.self) { try await store.delete(entry.id) }
        _ = try await store.setEnabled(entry.id, enabled: false)
        let reloaded = AgentSkillStore(paths: workspace.paths, builtInSkillsURL: bundle)
        #expect(try await reloaded.list().first?.enabled == false)
        #expect(!FileManager.default.fileExists(atPath: projection.path))
        await #expect(throws: AgentSkillStoreError.self) { try await reloaded.read(entry.id) }
        _ = try await reloaded.setEnabled(entry.id, enabled: true)
        #expect(try await reloaded.list().first?.enabled == true)
    }

    @Test("Existing enablement registries gain built-in skills without resetting user choices")
    func oldRegistry() async throws {
        let workspace = try NativeToolTestFixtures.workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try Data(#"{"version":1,"enabledSkillIDs":["user-skill"]}"#.utf8).write(to: workspace.paths.skillRegistryFile)
        let store = AgentSkillStore(paths: workspace.paths, builtInSkillsURL: NativeToolTestFixtures.skillDirectory.deletingLastPathComponent())
        #expect(try await store.list().first?.enabled == true)
        _ = try await store.setEnabled("native-tool-builder", enabled: false)
        let registry = try JSONDecoder().decode(AgentValue.self, from: Data(contentsOf: workspace.paths.skillRegistryFile))
        #expect(registry.objectValue?["enabledSkillIDs"] == .array([.string("user-skill")]))
    }
}
