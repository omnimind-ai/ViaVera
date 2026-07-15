import Foundation

struct IOSPermissionSettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let offersSystemSettings: Bool

    init(
        title: String,
        message: String,
        offersSystemSettings: Bool = false
    ) {
        self.title = title
        self.message = message
        self.offersSystemSettings = offersSystemSettings
    }
}
