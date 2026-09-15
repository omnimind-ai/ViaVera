import AVFoundation
import SwiftUI

#if os(iOS)
struct NativeToolCameraPreview: UIViewRepresentable {
    let camera: NativeToolCameraSession

    func makeUIView(context: Context) -> NativeToolCameraPreviewSurface {
        let view = NativeToolCameraPreviewSurface()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = camera.session
        return view
    }

    func updateUIView(_ view: NativeToolCameraPreviewSurface, context: Context) { view.setNeedsLayout() }

    static func dismantleUIView(_ view: NativeToolCameraPreviewSurface, coordinator: ()) {
        view.previewLayer.session = nil
    }
}
#else
struct NativeToolCameraPreview: NSViewRepresentable {
    let camera: NativeToolCameraSession

    func makeNSView(context: Context) -> NativeToolCameraPreviewSurface {
        let view = NativeToolCameraPreviewSurface()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = camera.session
        return view
    }

    func updateNSView(_ view: NativeToolCameraPreviewSurface, context: Context) { view.needsLayout = true }

    static func dismantleNSView(_ view: NativeToolCameraPreviewSurface, coordinator: ()) {
        view.previewLayer.session = nil
    }
}
#endif
