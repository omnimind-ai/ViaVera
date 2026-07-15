import SwiftUI

struct SkillSettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.skillSettings

        SettingsPageLayout(title: "Skills") {
            Section {
                if settings.isLoading, settings.skills.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("正在读取 Skills…")
                        Spacer()
                    }
                } else if settings.skills.isEmpty {
                    Color.clear
                        .frame(minHeight: 96)
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                } else {
                    ForEach(settings.skills) { skill in
                        SkillSettingsRow(
                            skill: skill,
                            isBusy: settings.busySkillIDs.contains(skill.id),
                            onSetEnabled: { enabled in
                                await settings.setEnabled(enabled, for: skill.id)
                            },
                            onDelete: {
                                deleteSkill(skill.id)
                            }
                        )
                    }
                }
            } header: {
                Text("已安装")
            }
        }
        .alert(item: $settings.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
        .task {
            await settings.load()
        }
    }

    private func deleteSkill(_ skillID: String) {
        Task {
            await appModel.skillSettings.deleteSkill(skillID)
        }
    }
}
