import PhotosUI
import SwiftUI
import Vision

struct TOTPImportView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TOTPManagerModel
    @State private var name = ""
    @State private var issuer = ""
    @State private var secret = ""
    @State private var algorithm: TOTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var photo: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isReading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("认证信息") {
                    PhotosPicker("从二维码图片导入", selection: $photo, matching: .images)
                        .disabled(isReading)
                    TextField("服务商（可选）", text: $issuer)
                    TextField("账户名称", text: $name)
                    SecureField("密钥或 otpauth 链接", text: $secret)
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                }
                Section("手动密钥参数") {
                    Picker("算法", selection: $algorithm) {
                        ForEach(TOTPAlgorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("验证码位数", selection: $digits) { Text("6 位").tag(6); Text("8 位").tag(8) }
                    TextField("周期（秒）", value: $period, format: .number)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("添加认证账户")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(secret.isEmpty || isReading) }
            }
            .task(id: photo) { await readQRCode() }
            .onDisappear { secret = ""; photo = nil }
            .privacySensitive()
        }
#if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
#endif
    }

    private func save() {
        do {
            try model.add(TOTPAccount.parse(secret, name: name, issuer: issuer, algorithm: algorithm, digits: digits, period: period))
            secret = ""
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func readQRCode() async {
        guard let photo else { return }
        isReading = true
        defer { isReading = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 20 * 1024 * 1024 else {
                throw NativeToolError("二维码图片无法读取或超过 20 MB。")
            }
            let payload = try await Task.detached(priority: .userInitiated) {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                try VNImageRequestHandler(data: data).perform([request])
                let matches = request.results?.compactMap(\.payloadStringValue).filter { $0.lowercased().hasPrefix("otpauth://totp/") } ?? []
                guard matches.count == 1, let match = matches.first else { throw NativeToolError("请选择只包含一个 TOTP 认证二维码的图片。") }
                _ = try TOTPAccount.parse(match)
                return match
            }.value
            try Task.checkCancellation()
            guard model.isUnlocked else { return }
            secret = payload
        } catch is CancellationError { }
        catch { errorMessage = "无法识别 TOTP 二维码，请检查图片或手动输入密钥。" }
    }
}
