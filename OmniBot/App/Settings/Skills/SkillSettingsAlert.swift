import Foundation

struct SkillSettingsAlert: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}
