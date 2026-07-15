import Foundation

struct SettingsSheetPresentation: Identifiable {
    let id = UUID()
    let initialDestination: SettingsCardDestination?

    init(initialDestination: SettingsCardDestination? = nil) {
        self.initialDestination = initialDestination
    }
}
