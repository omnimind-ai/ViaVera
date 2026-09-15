import AVFoundation
import SwiftUI

struct NativeToolCameraScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let authorize: () async -> Bool
    let isAuthorizing: () -> Bool
    let onScan: (String) -> Void
    @State private var camera = NativeToolCameraSession()
    @State private var isVisible = false
    @State private var isStarting = true
    @State private var errorMessage: String?
    @State private var hint = "将二维码放入取景框"
    @State private var startRequest = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    NativeToolCameraPreview(camera: camera)
                        .accessibilityHidden(true)
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                        .padding(32)
                        .accessibilityHidden(true)
                    if isStarting { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipShape(.rect(cornerRadius: 24))
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                    Button("重试", systemImage: "arrow.clockwise") { startRequest += 1 }
                } else {
                    Text(hint).foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("扫描二维码")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear { isVisible = true }
            .task(id: startRequest) { await start() }
            .onDisappear { isVisible = false; camera.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || (phase == .inactive && !isAuthorizing()) {
                    camera.stop()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: camera.session)) { _ in
                camera.stop()
                isStarting = false
                errorMessage = "相机暂时不可用，请重试或改用图片导入。"
            }
            .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: camera.session)) { _ in
                camera.stop()
                isStarting = false
                errorMessage = "相机使用已中断，请重试。"
            }
            .privacySensitive()
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
#endif
    }

    private func start() async {
        isStarting = true
        errorMessage = nil
        do {
            let authorized = await authorize()
            try Task.checkCancellation()
            guard isVisible else { return }
            guard authorized else {
                throw NativeToolError("请在系统设置中允许 Via Vera 使用相机，或返回后从图片、TXT 文件导入。")
            }
            camera.start { event in
                guard isVisible else { return }
                switch event {
                case .running: isStarting = false
                case let .hint(message): hint = message
                case let .failure(message): isStarting = false; errorMessage = message
                case let .payload(payload):
                    onScan(payload)
                    dismiss()
                }
            }
        } catch is CancellationError { }
        catch {
            guard isVisible else { return }
            isStarting = false
            errorMessage = error.localizedDescription
        }
    }
}
