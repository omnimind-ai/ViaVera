import Foundation

/// A main-window page, including the position inside a native tool.
struct AppNavigationLocation: Equatable {
    let destination: AppDestination
    let nativeToolPath: [UUID]
    let nativeToolScreenID: String?

    init(
        destination: AppDestination,
        nativeToolPath: [UUID] = [],
        nativeToolScreenID: String? = nil
    ) {
        self.destination = destination
        self.nativeToolPath = destination == .tools ? nativeToolPath : []
        self.nativeToolScreenID = destination == .tools && !nativeToolPath.isEmpty
            ? nativeToolScreenID : nil
    }
}
