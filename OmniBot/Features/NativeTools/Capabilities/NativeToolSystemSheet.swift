import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// Standard system surfaces shared by every package that invokes a capability.
struct NativeToolSystemSheet: View {
    let request: NativeToolSystemRequest
    let host: NativeToolHostCapabilities
    @State private var isSelectingFile = false
    @State private var isSavingFile = false
    @State private var photo: PhotosPickerItem?
    @State private var isReading = false

    var body: some View {
        Group {
            switch request.kind {
            case .camera:
                NativeToolCameraScannerView(authorize: host.authorizeCamera, isAuthorizing: { host.isAuthorizing }) {
                    complete(.success(.text($0)))
                }
            case .photo:
                NavigationStack {
                    VStack(spacing: 20) {
                        PhotosPicker("选择二维码图片", selection: $photo, matching: .images)
                            .disabled(isReading)
                        if isReading { ProgressView("正在识别二维码…") }
                    }
                    .padding(30)
                    .navigationTitle("二维码图片")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { complete(.failure(CancellationError())) } } }
                }
            case .openText, .openData:
                ProgressView("正在选择文件…").padding(40)
                    .fileImporter(isPresented: $isSelectingFile, allowedContentTypes: isTextRequest ? [.plainText] : [.data]) { result in
                        Task {
                            do {
                                let url = try result.get()
                                let data = try await Task.detached { try NativeToolSelectedFile.read(url) }.value
                                complete(.success(.data(data)))
                            } catch { complete(.failure(error)) }
                        }
                    }
                    .task { isSelectingFile = true }
            case let .save(data, name):
                ProgressView("正在导出文件…").padding(40)
                    .fileExporter(isPresented: $isSavingFile, document: NativeToolBinaryDocument(data: data), contentType: .data, defaultFilename: name) { result in
                        complete(result.map { _ in .confirmed(true) })
                    }
                    .task { isSavingFile = true }
            case let .confirm(title, message):
                VStack(alignment: .leading, spacing: 20) {
                    Text(title).font(.headline)
                    Text(message)
                    HStack {
                        Button("取消") { complete(.success(.confirmed(false))) }
                        Spacer()
                        Button("确认", role: .destructive) { complete(.success(.confirmed(true))) }
                    }
                }.padding(30)
            }
        }
        .privacySensitive()
        .task(id: photo) { await readPhoto() }
    }

    private var isTextRequest: Bool { if case .openText = request.kind { true } else { false } }

    private func complete(_ result: Result<NativeToolSystemResult, any Error>) { host.presentation.complete(result, id: request.id) }

    private func readPhoto() async {
        guard let photo else { return }
        isReading = true
        defer { isReading = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 20 * 1_024 * 1_024 else { throw NativeToolError("图片无法读取或超过 20 MB。") }
            let value = try await Task.detached {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                try VNImageRequestHandler(data: data).perform([request])
                return try NativeToolQRCodePayload.extract(request.results?.compactMap(\.payloadStringValue) ?? [])
            }.value
            try Task.checkCancellation()
            complete(.success(.text(value)))
        } catch { complete(.failure(error)) }
    }
}
