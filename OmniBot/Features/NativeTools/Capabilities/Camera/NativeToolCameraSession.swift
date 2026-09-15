import AVFoundation
import Foundation

/// All capture mutations, callbacks and lifecycle operations run on `queue`.
/// The main actor only attaches `session` to its native preview layer.
nonisolated final class NativeToolCameraSession: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "OmniBot.NativeTools.camera", qos: .userInitiated)
    private var handler: (@MainActor @Sendable (NativeToolCameraEvent) -> Void)?
    private var acceptsCodes = false
    private var lastHint: String?

    func start(handler: @escaping @MainActor @Sendable (NativeToolCameraEvent) -> Void) {
        queue.async {
            self.handler = handler
            self.acceptsCodes = true
            self.lastHint = nil
            do {
                try self.configure()
                self.session.startRunning()
                guard self.session.isRunning else { throw NativeToolError("相机暂时无法启动，请重试。") }
                self.emit(.running)
            } catch {
                self.acceptsCodes = false
                self.emit(.failure((error as? NativeToolError)?.localizedDescription ?? "无法打开相机，请检查相机是否被占用后重试。"))
            }
        }
    }

    func stop() {
        queue.async {
            self.acceptsCodes = false
            self.handler = nil
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
#if os(iOS)
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
#else
        let device = AVCaptureDevice.default(for: .video)
#endif
        guard let device else { throw NativeToolError("没有可用的相机。可以从二维码图片或 TXT 文件导入。") }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw NativeToolError("无法使用这台相机，请检查相机是否被占用。") }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { throw NativeToolError("相机不支持扫码，请从图片或 TXT 文件导入。") }
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            throw NativeToolError("相机不支持二维码识别，请从图片或 TXT 文件导入。")
        }
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(self, queue: queue)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard acceptsCodes else { return }
        let links = objects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard !links.isEmpty else { return }
        do {
            let payload = try NativeToolQRCodePayload.extract(links)
            acceptsCodes = false
            session.stopRunning()
            emit(.payload(payload))
        } catch {
            let hint = error.localizedDescription
            if hint != lastHint { lastHint = hint; emit(.hint(hint)) }
        }
    }

    private func emit(_ event: NativeToolCameraEvent) {
        guard let handler else { return }
        Task { @MainActor in handler(event) }
    }
}
