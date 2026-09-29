import SwiftUI

struct AppSceneLifecycleModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
#if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
#endif

    func body(content: Content) -> some View {
        content
            .task(start)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { appModel.cloudSync.requestSync() }
            }
            .alert("OmniBot 出现问题", isPresented: isErrorPresented) {
                Button("好", role: .cancel, action: dismissError)
            } message: {
                Text(appModel.globalErrorMessage ?? String(localized: "未知错误"))
            }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: {
#if os(macOS)
                // Only the active surface should present a shared application error.
                appearsActive && appModel.globalErrorMessage != nil
#else
                appModel.globalErrorMessage != nil
#endif
            },
            set: { isPresented in
                if !isPresented {
                    dismissError()
                }
            }
        )
    }

    private func start() async {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        await appModel.start()
    }

    private func dismissError() {
        appModel.globalErrorMessage = nil
    }
}
