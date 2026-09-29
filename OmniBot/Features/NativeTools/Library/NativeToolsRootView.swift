import SwiftUI

struct NativeToolsRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        NavigationStack(path: $appModel.nativeToolPath) {
            NativeToolLibraryView()
                .navigationDestination(for: UUID.self) { id in
                    NativeToolDetailView(toolID: id)
#if os(macOS)
                        .navigationBarBackButtonHidden()
#endif
                }
        }
#if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
    }
}
