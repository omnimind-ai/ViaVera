import Foundation
import Testing
@testable import Via_Vera

@Suite("Skill settings model")
@MainActor
struct SkillSettingsModelTests {
    @Test("Reflects import, enablement, and deletion")
    func lifecycle() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let source = temporary.root.appending(path: "model-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try skillDocument(name: "model-skill").write(
            to: source.appending(path: "SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = AgentSkillStore(paths: temporary.paths)
        let model = SkillSettingsModel(store: store)

        await model.load()
        #expect(model.skills.isEmpty)

        await model.importSkill(from: source)
        #expect(model.skills.count == 1)
        #expect(model.skills[0].id == "model-skill")
        #expect(!model.skills[0].enabled)
        #expect(model.alert == nil)

        let enabled = await model.setEnabled(true, for: "model-skill")
        #expect(enabled)
        #expect(model.skills[0].enabled)

        let deleted = await model.deleteSkill("model-skill")
        #expect(deleted)
        #expect(model.skills.isEmpty)
    }

    @Test("Presents a user-visible error for an invalid import")
    func invalidImportPresentsAlert() async throws {
        let temporary = try makeTemporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: temporary.root) }
        let invalidFile = temporary.root.appending(path: "not-a-skill.txt")
        try "invalid".write(to: invalidFile, atomically: true, encoding: .utf8)
        let model = SkillSettingsModel(
            store: AgentSkillStore(paths: temporary.paths)
        )

        await model.importSkill(from: invalidFile)

        #expect(model.skills.isEmpty)
        #expect(model.alert?.title == "无法导入 Skill")
        #expect(model.alert?.message.isEmpty == false)
    }

    private func skillDocument(name: String) -> String {
        """
        ---
        name: \(name)
        description: Settings model test
        compatibility: apple
        ---
        Test instructions.
        """
    }
}
