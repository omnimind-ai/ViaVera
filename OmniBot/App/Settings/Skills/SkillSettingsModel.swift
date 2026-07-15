import Foundation
import Observation

@MainActor
@Observable
final class SkillSettingsModel {
    private let store: AgentSkillStore

    private(set) var skills: [AgentSkillIndexEntry] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var busySkillIDs: Set<String> = []
    var alert: SkillSettingsAlert?

    var isMutating: Bool {
        isImporting || !busySkillIDs.isEmpty
    }

    init(store: AgentSkillStore) {
        self.store = store
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            skills = try await store.list()
        } catch {
            presentError(error, title: "无法读取 Skills")
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, for skillID: String) async -> Bool {
        guard !busySkillIDs.contains(skillID),
              let current = skills.first(where: { $0.id == skillID }) else {
            return skills.first(where: { $0.id == skillID })?.enabled ?? false
        }
        busySkillIDs.insert(skillID)
        defer { busySkillIDs.remove(skillID) }
        do {
            let updated = try await store.setEnabled(skillID, enabled: enabled)
            replace(updated)
            return updated.enabled
        } catch {
            presentError(error, title: enabled ? "无法启用 Skill" : "无法停用 Skill")
            return current.enabled
        }
    }

    func importSkill(from sourceURL: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let imported = try await store.importSkill(from: sourceURL)
            skills.append(imported)
            sortSkills()
        } catch {
            presentError(error, title: "无法导入 Skill")
        }
    }

    @discardableResult
    func deleteSkill(_ skillID: String) async -> Bool {
        guard !busySkillIDs.contains(skillID) else { return false }
        busySkillIDs.insert(skillID)
        defer { busySkillIDs.remove(skillID) }
        do {
            try await store.delete(skillID)
            skills.removeAll { $0.id == skillID }
            return true
        } catch {
            presentError(error, title: "无法删除 Skill")
            return false
        }
    }

    private func replace(_ entry: AgentSkillIndexEntry) {
        guard let index = skills.firstIndex(where: { $0.id == entry.id }) else {
            skills.append(entry)
            sortSkills()
            return
        }
        skills[index] = entry
    }

    private func sortSkills() {
        skills.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func presentError(_ error: any Error, title: String) {
        alert = SkillSettingsAlert(
            title: title,
            message: error.localizedDescription
        )
    }
}
