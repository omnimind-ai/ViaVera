#if os(macOS)
import Foundation

extension AppModel {
    var canGoBack: Bool {
        presentedSettingsDestination == nil
            && navigationHistory.canGoBack(where: isNavigationLocationAvailable)
    }

    var canGoForward: Bool {
        presentedSettingsDestination == nil
            && navigationHistory.canGoForward(where: isNavigationLocationAvailable)
    }

    func goBack() {
        guard canGoBack,
              let location = navigationHistory.goBack(where: isNavigationLocationAvailable) else { return }
        restoreNavigation(location)
    }

    func goForward() {
        guard canGoForward,
              let location = navigationHistory.goForward(where: isNavigationLocationAvailable) else { return }
        restoreNavigation(location)
    }

    func openNativeToolLibrary() {
        // Change the path first so entering from a chat records only the library,
        // rather than the tool that was open on the previous visit.
        nativeToolPath = []
        destination = .tools
    }

    func recordNavigationVisit() {
        guard !isRestoringNavigation, let destination else { return }
        navigationHistory.visit(AppNavigationLocation(
            destination: destination,
            nativeToolPath: nativeToolPath,
            nativeToolScreenID: nativeToolScreenID
        ))
    }

    private func restoreNavigation(_ location: AppNavigationLocation) {
        isRestoringNavigation = true
        defer { isRestoringNavigation = false }
        if location.destination == .tools {
            nativeToolPath = location.nativeToolPath
            nativeToolScreenID = location.nativeToolScreenID
        }
        destination = location.destination
    }

    private func isNavigationLocationAvailable(_ location: AppNavigationLocation) -> Bool {
        switch location.destination {
        case let .conversation(id):
            return conversations.conversation(id: id) != nil
        case .tools:
            guard location.nativeToolPath.allSatisfy({ id in
                nativeTools.records.contains { $0.id == id }
            }) else { return false }
            if let screenID = location.nativeToolScreenID {
                return nativeTools.records.first(where: { $0.id == location.nativeToolPath.last })?
                    .package.screens.contains(where: { $0.id == screenID }) == true
            }
            return true
        default:
            return true
        }
    }
}
#endif
