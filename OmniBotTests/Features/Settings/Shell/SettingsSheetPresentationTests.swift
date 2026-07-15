import Testing
@testable import Via_Vera

@Suite("Settings sheet presentation")
@MainActor
struct SettingsSheetPresentationTests {
    @Test("Preserves the requested initial settings destination")
    func preservesInitialDestination() {
        #expect(SettingsSheetPresentation().initialDestination == nil)
        #expect(
            SettingsSheetPresentation(initialDestination: .workspace).initialDestination
                == .workspace
        )
    }
}
