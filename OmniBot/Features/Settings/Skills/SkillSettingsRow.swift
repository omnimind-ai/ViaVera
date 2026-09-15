import SwiftUI

struct SkillSettingsRow: View {
    let skill: AgentSkillIndexEntry
    let isBusy: Bool
    let onSetEnabled: (Bool) async -> Bool
    let onDelete: () -> Void

    @State private var isEnabled: Bool
    @State private var isApplying = false
    @State private var isConfirmingDelete = false

    init(
        skill: AgentSkillIndexEntry,
        isBusy: Bool,
        onSetEnabled: @escaping (Bool) async -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self.skill = skill
        self.isBusy = isBusy
        self.onSetEnabled = onSetEnabled
        self.onDelete = onDelete
        _isEnabled = State(initialValue: skill.enabled)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppDesign.standardSpacing) {
            VStack(alignment: .leading, spacing: AppDesign.compactSpacing) {
                Text(skill.displayName)
                    .font(.body)

                if !skill.displayDescription.isEmpty {
                    Text(skill.displayDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Text(skill.isBuiltIn ? "内置 · \(skill.id)" : skill.id)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("启用 \(skill.displayName)", isOn: $isEnabled)
                .labelsHidden()
                .disabled(isApplying || isBusy)
                .frame(minWidth: 44, minHeight: 44)

            if !skill.isBuiltIn {
                Menu("Skill 操作", systemImage: "ellipsis.circle") {
                    Button("删除", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(isApplying || isBusy)
                .frame(minWidth: 44, minHeight: 44)
                .confirmationDialog(
                    "删除 \(skill.displayName)？",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("删除", role: .destructive, action: onDelete)
                } message: {
                    Text("删除后，此 Skill 将不再供 Agent 使用。")
                }
            }
        }
        .onChange(of: isEnabled) { _, newValue in
            applyEnabledState(newValue)
        }
        .onChange(of: skill.enabled) { _, newValue in
            if !isApplying {
                isEnabled = newValue
            }
        }
    }

    private func applyEnabledState(_ requestedValue: Bool) {
        guard !isApplying, requestedValue != skill.enabled else { return }
        isApplying = true
        Task {
            isEnabled = await onSetEnabled(requestedValue)
            isApplying = false
        }
    }
}
