import SwiftUI

struct NativeToolsRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        NavigationStack(path: $appModel.nativeToolPath) {
            NativeToolLibraryView()
                .navigationDestination(for: UUID.self) { id in
                    NativeToolDetailView(toolID: id)
                }
        }
    }
}
